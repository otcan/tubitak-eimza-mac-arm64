# Third-party software

## Amazon Corretto 8 / OpenJDK

The build downloads Amazon Corretto 8.512.09.1 for macOS ARM64 from Amazon's official download service. Corretto is an OpenJDK distribution under the GNU General Public License, version 2, with the Classpath Exception and additional notices for included components.

The generated application includes the distribution's `LICENSE`, `ASSEMBLY_EXCEPTION`, and `THIRD_PARTY_README` files under `Contents/Resources/Licenses`, along with notices present in its runtime directory.

- [Corretto 8 source and licensing](https://github.com/corretto/corretto-8)
- [Official downloads](https://docs.aws.amazon.com/corretto/latest/corretto-8-ug/downloads-list.html)

No Java runtime binary is committed to this repository.

## TÜBİTAK signing application and libraries

The build downloads `sublimity-esign-client-swingui-1.21.0-SNAPSHOT-jar-with-dependencies.jar` directly from TÜBİTAK's `e-imza.tubitak.gov.tr` service. Its SHA-256 is pinned in the build scripts and its original JAR signature is verified.

This repository does not contain or relicense TÜBİTAK's application, ESYA/MA3 libraries, or their bundled dependencies. Those components retain their original ownership, licensing, and service requirements. The helper supplies the launch environment; it does not patch the original JAR.

## AKİS and other card drivers

Card drivers are installed separately from their publishers and are not bundled or relicensed by this project. AKİS drivers are available from [TÜBİTAK BİLGEM](https://akiskart.bilgem.tubitak.gov.tr/tr/destek/).
