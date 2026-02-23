################################################################################
#
# python-xdis
#
################################################################################

PYTHON_XDIS_VERSION = 6.1.8
PYTHON_XDIS_SOURCE = xdis-6.1.8.tar.gz
PYTHON_XDIS_SITE = https://files.pythonhosted.org/packages/31/53/40c259fba51acb5ae83a0ecee4aa0837c57d2fa0e29bd7391fe041bfee7f
PYTHON_XDIS_SETUP_TYPE = setuptools
PYTHON_XDIS_LICENSE = GPL-2.0
PYTHON_XDIS_DEPENDENCIES = python-click

$(eval $(python-package))
