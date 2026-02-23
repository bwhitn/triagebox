################################################################################
#
# python-minidump
#
################################################################################

PYTHON_MINIDUMP_VERSION = 0.0.24
PYTHON_MINIDUMP_SOURCE = minidump-0.0.24.tar.gz
PYTHON_MINIDUMP_SITE = https://files.pythonhosted.org/packages/26/4b/bc695b99dc7d77d28223765c3ee5a31d34fd2850c52eb683ccdd1206067d
PYTHON_MINIDUMP_SETUP_TYPE = setuptools
PYTHON_MINIDUMP_LICENSE = UNKNOWN

$(eval $(python-package))
