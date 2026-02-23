################################################################################
#
# python-pycdlib
#
################################################################################

PYTHON_PYCDLIB_VERSION = 1.14.0
PYTHON_PYCDLIB_SOURCE = pycdlib-1.14.0.tar.gz
PYTHON_PYCDLIB_SITE = https://files.pythonhosted.org/packages/62/d3/52b8dd7a862aec7cc4043a520490bfc9b408179dc374d0e3416fb0614a86
PYTHON_PYCDLIB_SETUP_TYPE = setuptools
PYTHON_PYCDLIB_LICENSE = LGPLv2

$(eval $(python-package))
