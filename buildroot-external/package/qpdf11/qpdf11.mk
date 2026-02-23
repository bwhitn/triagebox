################################################################################
#
# qpdf11
#
################################################################################

QPDF11_VERSION = v11.9.1
QPDF11_SITE = https://github.com/qpdf/qpdf.git
QPDF11_SITE_METHOD = git
QPDF11_INSTALL_STAGING = YES
QPDF11_SUPPORTS_IN_SOURCE_BUILD = NO
QPDF11_LICENSE = Apache-2.0 or Artistic-2.0
QPDF11_LICENSE_FILES = LICENSE.txt Artistic-2.0
QPDF11_DEPENDENCIES = host-pkgconf zlib jpeg

QPDF11_CONF_OPTS = \
	-DBUILD_DOC=OFF \
	-DBUILD_TESTING=OFF \
	-DBUILD_STATIC_LIBS=OFF \
	-DBUILD_SHARED_LIBS=ON \
	-DINSTALL_MANUAL=OFF \
	-DINSTALL_EXAMPLES=OFF \
	-DUSE_IMPLICIT_CRYPTO=OFF \
	-DALLOW_CRYPTO_NATIVE=ON \
	-DREQUIRE_CRYPTO_NATIVE=ON \
	-DREQUIRE_CRYPTO_OPENSSL=OFF \
	-DREQUIRE_CRYPTO_GNUTLS=OFF

$(eval $(cmake-package))
