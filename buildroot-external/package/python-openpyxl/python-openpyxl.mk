################################################################################
#
# python-openpyxl
#
################################################################################

PYTHON_OPENPYXL_VERSION = 3.2.0b1
PYTHON_OPENPYXL_SOURCE = openpyxl-3.2.0b1.tar.gz
PYTHON_OPENPYXL_SITE = https://files.pythonhosted.org/packages/d0/ba/a48d1d7b5ff6f8628a76115fdf1f86bfff519ebef87be2ce2fcc0f344370
PYTHON_OPENPYXL_SETUP_TYPE = setuptools
PYTHON_OPENPYXL_LICENSE = MIT

$(eval $(python-package))
