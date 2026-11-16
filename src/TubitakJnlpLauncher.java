import java.applet.*;
import java.awt.*;
import java.awt.event.*;
import java.io.*;
import java.net.*;
import java.nio.file.*;
import java.util.*;
import java.util.logging.*;
import javax.swing.*;
import javax.xml.parsers.*;
import org.w3c.dom.*;

/** Local host for the unchanged official TÜBİTAK signing applet. */
public final class TubitakJnlpLauncher implements AppletStub, AppletContext {
    private static final String BASE = "https://e-imza.tubitak.gov.tr/sublimity-ess/jnlp/";
    private static final String APPLET = "tr.gov.tubitak.sublimity.esign.client.swingui.app.SignApplet";
    private static final String JAR = "sublimity-esign-client-swingui-1.21.0-SNAPSHOT-jar-with-dependencies.jar";
    private final Map<String,String> parameters = new HashMap<>();
    private final Map<String,InputStream> streams = new HashMap<>();
    private final URL documentBase;
    private Applet applet;
    private JFrame frame;

    private TubitakJnlpLauncher(Path path) throws Exception {
        this(readDocument(path));
    }

    private static Document readDocument(Path path) throws Exception {
        if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS) || Files.size(path) > 1048576)
            throw new IOException("Choose a regular TÜBİTAK JNLP file smaller than 1 MiB.");
        try (InputStream input = Files.newInputStream(path)) {
            return parseDocument(readBounded(input));
        }
    }

    private static byte[] readBounded(InputStream input) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int count;
        while ((count = input.read(buffer)) != -1) {
            if (bytes.size() + count > 1048576) throw new IOException("Signing request is too large.");
            bytes.write(buffer, 0, count);
        }
        return bytes.toByteArray();
    }

    private static Document parseDocument(byte[] data) throws Exception {
        if (data.length > 1048576) throw new IOException("Signing request is too large.");
        DocumentBuilderFactory f = DocumentBuilderFactory.newInstance();
        f.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
        f.setFeature("http://xml.org/sax/features/external-general-entities", false);
        f.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
        f.setXIncludeAware(false);
        f.setExpandEntityReferences(false);
        return f.newDocumentBuilder().parse(new ByteArrayInputStream(data));
    }

    private TubitakJnlpLauncher(Document d) throws Exception {
        Element root = d.getDocumentElement();
        if (!"jnlp".equals(root.getTagName()) || !BASE.equals(root.getAttribute("codebase")))
            throw new IOException("This launcher accepts only the official TÜBİTAK signing codebase.");
        documentBase = new URL(new URL(BASE), root.getAttribute("href"));
        if (!documentBase.toExternalForm().startsWith(BASE) || documentBase.getQuery() != null
                || documentBase.getRef() != null
                || !documentBase.getPath().matches("/sublimity-ess/jnlp/[A-Za-z0-9_-]+\\.jnlp"))
            throw new IOException("Unexpected JNLP document URL.");
        NodeList jars = root.getElementsByTagName("jar");
        if (jars.getLength() != 1 || !JAR.equals(((Element)jars.item(0)).getAttribute("href")))
            throw new IOException("TÜBİTAK changed the application version. Review the new official package first.");
        NodeList applets = root.getElementsByTagName("applet-desc");
        if (applets.getLength() != 1 || !APPLET.equals(((Element)applets.item(0)).getAttribute("main-class")))
            throw new IOException("Unexpected applet class.");
        NodeList params = ((Element)applets.item(0)).getElementsByTagName("param");
        for (int i=0; i<params.getLength(); i++) {
            Element p = (Element)params.item(i);
            if (parameters.put(p.getAttribute("name"), p.getAttribute("value")) != null)
                throw new IOException("Duplicate signing parameter.");
        }
        if (parameters.get("job") == null || parameters.get("job").trim().isEmpty())
            throw new IOException("Missing signing job.");
        if (!"https://e-imza.tubitak.gov.tr/sublimity-ess/jobs/".equals(parameters.get("getAddress"))
                || !"https://e-imza.tubitak.gov.tr/checkJob.htm".equals(parameters.get("checkAddress")))
            throw new IOException("Unexpected signing server. No request was sent.");
    }

    private static TubitakJnlpLauncher refresh(TubitakJnlpLauncher original) throws Exception {
        HttpURLConnection connection = (HttpURLConnection)original.documentBase.openConnection();
        connection.setInstanceFollowRedirects(false);
        connection.setConnectTimeout(15000);
        connection.setReadTimeout(20000);
        try {
            if (connection.getResponseCode() != 200)
                throw new IOException("Download a fresh signing request from TÜBİTAK.");
            byte[] bytes;
            try (InputStream input = connection.getInputStream()) {
                bytes = readBounded(input);
            }
            TubitakJnlpLauncher updated = new TubitakJnlpLauncher(parseDocument(bytes));
            if (!Objects.equals(original.parameters.get("job"), updated.parameters.get("job")))
                throw new IOException("The signing job changed unexpectedly. No signing client was started.");
            return updated;
        } finally {
            connection.disconnect();
        }
    }

    public static void main(String[] args) throws Exception {
        Logger.getLogger("").setLevel(Level.WARNING);
        if (args.length == 1 && "--check-card".equals(args[0])) {
            checkCard();
            return;
        }
        if (args.length == 2 && "--validate".equals(args[0])) {
            new TubitakJnlpLauncher(Paths.get(args[1]));
            System.out.println("VALID_TUBITAK_REQUEST");
            return;
        }
        if (args.length != 1) throw new IllegalArgumentException("Pass one TÜBİTAK .jnlp file.");
        final TubitakJnlpLauncher host = refresh(new TubitakJnlpLauncher(Paths.get(args[0])));
        SwingUtilities.invokeLater(() -> {
            try {
                host.applet = (Applet)Class.forName(APPLET).newInstance();
                host.applet.setStub(host);
                host.frame = new JFrame("TÜBİTAK E-İmza — Official signing client");
                host.frame.setDefaultCloseOperation(WindowConstants.DO_NOTHING_ON_CLOSE);
                host.frame.addWindowListener(new WindowAdapter() {
                    public void windowClosing(WindowEvent event) {
                        host.applet.stop();
                        host.applet.destroy();
                        host.frame.dispose();
                        System.exit(0);
                    }
                });
                host.frame.setContentPane((Container)host.applet);
                host.frame.setSize(860, 520);
                host.frame.setLocationRelativeTo(null);
                host.frame.setVisible(true);
                host.applet.init();
                host.applet.start();
                host.frame.validate();
                java.lang.reflect.Field jobField = host.applet.getClass().getDeclaredField("esignJob");
                jobField.setAccessible(true);
                if (jobField.get(host.applet) == null) {
                    JOptionPane.showMessageDialog(host.frame,
                        "TÜBİTAK did not return any documents for this signing request.\n"
                        + "Download a fresh .jnlp from your TÜBİTAK signing queue and open it here.",
                        "Signing request unavailable", JOptionPane.INFORMATION_MESSAGE);
                    host.frame.dispose();
                    System.exit(2);
                }
            } catch (Throwable error) {
                error.printStackTrace();
                JOptionPane.showMessageDialog(host.frame,
                    error.getClass().getSimpleName() + ": " + error.getMessage(),
                    "TÜBİTAK launcher", JOptionPane.ERROR_MESSAGE);
            }
        });
    }

    private static void checkCard() throws Exception {
        tr.gov.tubitak.sublimity.esign.client.core.conf.NxESignPlatformLibSelector.findPCSCLib();
        tr.gov.tubitak.sublimity.common.core.KamuSMBaseConf.initLicense();
        tr.gov.tubitak.uekae.esya.api.smartcard.config.SmartCardConfigParser parser =
            new tr.gov.tubitak.uekae.esya.api.smartcard.config.SmartCardConfigParser();
        tr.gov.tubitak.uekae.esya.api.smartcard.pkcs11.CardType.applyCardTypeConfig(
            parser.readConfig(tr.gov.tubitak.sublimity.common.core.KamuSMBaseConf.getATRListFileAsStream()));
        java.util.List<String> readers =
            tr.gov.tubitak.sublimity.esign.client.core.ESignClientCoreSmartCard.getCardTerminals();
        int cards = 0, certificates = 0;
        for (String reader : readers) {
            if (!tr.gov.tubitak.sublimity.esign.client.core.ESignClientCoreSmartCard.isCardPresent(reader)) continue;
            cards++;
            tr.gov.tubitak.uekae.esya.api.common.util.bag.Pair<Long,
                tr.gov.tubitak.uekae.esya.api.smartcard.pkcs11.CardType> info =
                tr.gov.tubitak.uekae.esya.api.smartcard.pkcs11.SmartOp.getSlotAndCardType(reader);
            tr.gov.tubitak.uekae.esya.api.smartcard.pkcs11.P11SmartCard card =
                new tr.gov.tubitak.uekae.esya.api.smartcard.pkcs11.P11SmartCard(info.second());
            try {
                card.openSession(info.first());
                certificates += card.getSignatureCertificates().size();
            } finally {
                if (card.isSessionActive()) card.closeSession();
            }
        }
        System.out.println("CARD_CHECK readers=" + readers.size() + " cards=" + cards
            + " certificates=" + certificates + " runtime=" + System.getProperty("java.version")
            + " arch=" + System.getProperty("os.arch"));
    }

    public boolean isActive() { return true; }
    public URL getDocumentBase() { return documentBase; }
    public URL getCodeBase() { try { return new URL(BASE); } catch (Exception e) { throw new AssertionError(e); } }
    public String getParameter(String name) { return parameters.get(name); }
    public AppletContext getAppletContext() { return this; }
    public void appletResize(int width, int height) { }
    public AudioClip getAudioClip(URL url) { return Applet.newAudioClip(url); }
    public Image getImage(URL url) { return Toolkit.getDefaultToolkit().getImage(url); }
    public Applet getApplet(String name) { return applet; }
    public Enumeration<Applet> getApplets() { return Collections.enumeration(Collections.singleton(applet)); }
    public void showDocument(URL url) { showDocument(url, "_blank"); }
    public void showDocument(URL url, String target) {
        if (!"https".equals(url.getProtocol()) || !"e-imza.tubitak.gov.tr".equals(url.getHost())) return;
        try { Desktop.getDesktop().browse(url.toURI()); } catch (Exception e) { showStatus("Please return to the TÜBİTAK browser page."); }
    }
    public void showStatus(String status) { if (frame != null) frame.setTitle("TÜBİTAK E-İmza — " + status); }
    public void setStream(String key, InputStream stream) { streams.put(key, stream); }
    public InputStream getStream(String key) { return streams.get(key); }
    public Iterator<String> getStreamKeys() { return streams.keySet().iterator(); }
}
