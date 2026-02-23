################################################################################
#
# python-pefile-target
#
################################################################################

PYTHON_PEFILE_TARGET_VERSION = 2024.8.26
PYTHON_PEFILE_TARGET_SOURCE = pefile-$(PYTHON_PEFILE_TARGET_VERSION).tar.gz
PYTHON_PEFILE_TARGET_SITE = https://files.pythonhosted.org/packages/03/4f/2750f7f6f025a1507cd3b7218691671eecfd0bbebebe8b39aa0fe1d360b8
PYTHON_PEFILE_TARGET_SETUP_TYPE = setuptools
PYTHON_PEFILE_TARGET_LICENSE = MIT
PYTHON_PEFILE_TARGET_LICENSE_FILES = LICENSE

$(eval $(python-package))
