################################################################################
#
# python-inflate64
#
################################################################################

PYTHON_INFLATE64_VERSION = 1.0.3
PYTHON_INFLATE64_SOURCE = inflate64-$(PYTHON_INFLATE64_VERSION).tar.gz
PYTHON_INFLATE64_SITE = https://files.pythonhosted.org/packages/source/i/inflate64
PYTHON_INFLATE64_SETUP_TYPE = setuptools
PYTHON_INFLATE64_LICENSE = UNKNOWN

$(eval $(python-package))
