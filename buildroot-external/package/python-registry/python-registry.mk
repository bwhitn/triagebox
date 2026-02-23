################################################################################
#
# python-registry
#
################################################################################

PYTHON_REGISTRY_VERSION = 1.3.1
PYTHON_REGISTRY_SOURCE = python-registry-1.3.1.tar.gz
PYTHON_REGISTRY_SITE = https://files.pythonhosted.org/packages/a4/82/c9ae8e9764eae863a4d63c05d5f2d767e392b523c2976c16c56f9a3b17b4
PYTHON_REGISTRY_SETUP_TYPE = setuptools
PYTHON_REGISTRY_LICENSE = Apache License (2.0)

$(eval $(python-package))
