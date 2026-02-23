################################################################################
#
# python-capstone
#
################################################################################

PYTHON_CAPSTONE_VERSION = 6.0.0a7
PYTHON_CAPSTONE_SOURCE = capstone-6.0.0a7.tar.gz
PYTHON_CAPSTONE_SITE = https://files.pythonhosted.org/packages/7e/1c/f209b80aa02faf5000d6db935364fdc5dcacca1d5dce446b0a4b88fe0f7c
PYTHON_CAPSTONE_SETUP_TYPE = setuptools
PYTHON_CAPSTONE_LICENSE = UNKNOWN

$(eval $(python-package))
