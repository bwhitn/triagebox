################################################################################
#
# python-backports-lzma
#
################################################################################

PYTHON_BACKPORTS_LZMA_VERSION = 0.0.14
PYTHON_BACKPORTS_LZMA_SOURCE = backports.lzma-$(PYTHON_BACKPORTS_LZMA_VERSION).tar.gz
PYTHON_BACKPORTS_LZMA_SITE = https://files.pythonhosted.org/packages/source/b/backports.lzma
PYTHON_BACKPORTS_LZMA_SETUP_TYPE = setuptools
PYTHON_BACKPORTS_LZMA_LICENSE = Python-2.0

$(eval $(python-package))
