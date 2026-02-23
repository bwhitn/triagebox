################################################################################
#
# python-pikepdf
#
################################################################################

PYTHON_PIKEPDF_VERSION = 9.4.2
PYTHON_PIKEPDF_SOURCE = pikepdf-9.4.2.tar.gz
PYTHON_PIKEPDF_SITE = https://files.pythonhosted.org/packages/57/54/71552c3ab2694618741e5579506759238716664400304cb615917a993df5
PYTHON_PIKEPDF_SETUP_TYPE = setuptools
PYTHON_PIKEPDF_LICENSE = UNKNOWN
PYTHON_PIKEPDF_DEPENDENCIES = python-pybind

$(eval $(python-package))
