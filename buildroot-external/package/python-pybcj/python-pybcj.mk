################################################################################
#
# python-pybcj
#
################################################################################

PYTHON_PYBCJ_VERSION = 1.0.7
PYTHON_PYBCJ_SOURCE = pybcj-$(PYTHON_PYBCJ_VERSION).tar.gz
PYTHON_PYBCJ_SITE = https://files.pythonhosted.org/packages/source/p/pybcj
PYTHON_PYBCJ_SETUP_TYPE = setuptools
PYTHON_PYBCJ_LICENSE = UNKNOWN

$(eval $(python-package))
