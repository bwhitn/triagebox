################################################################################
#
# python-pyzstd
#
################################################################################

PYTHON_PYZSTD_VERSION = 0.19.1
PYTHON_PYZSTD_SOURCE = pyzstd-0.19.1.tar.gz
PYTHON_PYZSTD_SITE = https://files.pythonhosted.org/packages/4c/66/59fed71d0d2065e02974b40296f836a237c364c8bbe07295f2d0dc33c278
PYTHON_PYZSTD_SETUP_TYPE = pep517
PYTHON_PYZSTD_LICENSE = UNKNOWN

$(eval $(python-package))
