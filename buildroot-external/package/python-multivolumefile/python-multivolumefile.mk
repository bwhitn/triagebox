################################################################################
#
# python-multivolumefile
#
################################################################################

PYTHON_MULTIVOLUMEFILE_VERSION = 0.2.3
PYTHON_MULTIVOLUMEFILE_SOURCE = multivolumefile-$(PYTHON_MULTIVOLUMEFILE_VERSION).tar.gz
PYTHON_MULTIVOLUMEFILE_SITE = https://files.pythonhosted.org/packages/50/f0/a7786212b5a4cb9ba05ae84a2bbd11d1d0279523aea0424b6d981d652a14
PYTHON_MULTIVOLUMEFILE_SETUP_TYPE = setuptools
PYTHON_MULTIVOLUMEFILE_LICENSE = UNKNOWN

$(eval $(python-package))
