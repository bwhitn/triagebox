################################################################################
#
# python-pyppmd
#
################################################################################

PYTHON_PYPPMD_VERSION = 1.3.1
PYTHON_PYPPMD_SOURCE = pyppmd-1.3.1.tar.gz
PYTHON_PYPPMD_SITE = https://files.pythonhosted.org/packages/81/d7/803232913cab9163a1a97ecf2236cd7135903c46ac8d49613448d88e8759
PYTHON_PYPPMD_SETUP_TYPE = setuptools
PYTHON_PYPPMD_LICENSE = LGPL-2.1-or-later

$(eval $(python-package))
