################################################################################
#
# python-pyzbar
#
################################################################################

PYTHON_PYZBAR_VERSION = 0.1.9
PYTHON_PYZBAR_SOURCE = pyzbar-$(PYTHON_PYZBAR_VERSION).tar.gz
PYTHON_PYZBAR_SITE = $(call github,NaturalHistoryMuseum,pyzbar,v$(PYTHON_PYZBAR_VERSION))
PYTHON_PYZBAR_SETUP_TYPE = setuptools
PYTHON_PYZBAR_LICENSE = MIT
PYTHON_PYZBAR_LICENSE_FILES = LICENSE.txt
PYTHON_PYZBAR_DEPENDENCIES = zbar

$(eval $(python-package))
