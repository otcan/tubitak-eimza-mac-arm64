"""Validate synthetic requests without a card, real signing job, or network calls."""
import copy
import subprocess
import sys
import tempfile
from pathlib import Path
from xml.etree import ElementTree as ET

java, classpath = sys.argv[1:]
base = "https://e-imza.tubitak.gov.tr/sublimity-ess/jnlp/"
root = ET.Element("jnlp", codebase=base, href="example-request.jnlp")
resources = ET.SubElement(root, "resources")
ET.SubElement(resources, "java", version="1.8*")
ET.SubElement(resources, "jar", href="sublimity-esign-client-swingui-1.21.0-SNAPSHOT-jar-with-dependencies.jar")
applet = ET.SubElement(root, "applet-desc", {"main-class": "tr.gov.tubitak.sublimity.esign.client.swingui.app.SignApplet"})
for name, value in {
    "job": "synthetic-example-not-a-real-job",
    "getAddress": "https://e-imza.tubitak.gov.tr/sublimity-ess/jobs/",
    "checkAddress": "https://e-imza.tubitak.gov.tr/checkJob.htm",
}.items():
    ET.SubElement(applet, "param", name=name, value=value)

cases = [("official descriptor structure", ET.tostring(root), True)]

def mutation(name, change):
    changed = copy.deepcopy(root)
    change(changed)
    cases.append((name, ET.tostring(changed), False))

mutation("foreign codebase", lambda r: r.set("codebase", "https://example.invalid/sublimity-ess/jnlp/"))
mutation("lookalike host", lambda r: r.set("codebase", "https://e-imza.tubitak.gov.tr.example.invalid/sublimity-ess/jnlp/"))
mutation("foreign JNLP URL", lambda r: r.set("href", "https://example.invalid/example.jnlp"))
mutation("JNLP path traversal", lambda r: r.set("href", "../example.jnlp"))
mutation("JNLP fragment", lambda r: r.set("href", "example.jnlp#fragment"))
mutation("unreviewed JAR", lambda r: r.find("./resources/jar").set("href", "other.jar"))
mutation("foreign signing destination", lambda r: r.find("./applet-desc/param[@name='getAddress']").set("value", "https://example.invalid/jobs/"))
mutation("missing job", lambda r: r.find("applet-desc").remove(r.find("./applet-desc/param[@name='job']")))
mutation("duplicate parameter", lambda r: ET.SubElement(r.find("applet-desc"), "param", name="job", value="duplicate"))
mutation("unexpected applet", lambda r: r.find("applet-desc").set("main-class", "other.Main"))
cases.append(("external XML entity", b'<!DOCTYPE jnlp [<!ENTITY secret SYSTEM "file:///etc/passwd">]>' + ET.tostring(root), False))
cases.append(("oversized request", ET.tostring(root) + b" " * 1_048_577, False))

with tempfile.TemporaryDirectory(prefix="tubitak-parser-test-") as directory:
    for index, (name, content, expected) in enumerate(cases):
        file = Path(directory) / f"request-{index}.jnlp"
        file.write_bytes(content)
        result = subprocess.run([java, "-cp", classpath, "TubitakJnlpLauncher", "--validate", str(file)],
                                capture_output=True, text=True, timeout=15)
        assert (result.returncode == 0) == expected, f"Failed: {name}\n{result.stderr}"
        print(f"PASS: {name}")
    link = Path(directory) / "symlink.jnlp"
    link.symlink_to(Path(directory) / "request-0.jnlp")
    result = subprocess.run([java, "-cp", classpath, "TubitakJnlpLauncher", "--validate", str(link)],
                            capture_output=True, text=True, timeout=15)
    assert result.returncode != 0, "A symbolic link should be rejected"
    print("PASS: symbolic link")
