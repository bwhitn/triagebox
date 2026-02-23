################################################################################
#
# python-oletools
#
################################################################################

PYTHON_OLETOOLS_VERSION = 0.60.2
PYTHON_OLETOOLS_SOURCE = oletools-$(PYTHON_OLETOOLS_VERSION).tar.gz
PYTHON_OLETOOLS_SITE = https://files.pythonhosted.org/packages/source/o/oletools
PYTHON_OLETOOLS_SETUP_TYPE = setuptools
PYTHON_OLETOOLS_LICENSE = BSD

$(eval $(python-package))
