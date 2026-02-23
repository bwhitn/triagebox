################################################################################
#
# python-untangle
#
################################################################################

PYTHON_UNTANGLE_VERSION = 1.2.1
PYTHON_UNTANGLE_SOURCE = untangle-$(PYTHON_UNTANGLE_VERSION).tar.gz
PYTHON_UNTANGLE_SITE = $(call pypi,untangle,untangle)
PYTHON_UNTANGLE_SETUP_TYPE = setuptools
PYTHON_UNTANGLE_LICENSE = UNKNOWN

$(eval $(python-package))
