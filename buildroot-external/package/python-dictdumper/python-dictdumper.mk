################################################################################
#
# python-dictdumper
#
################################################################################

PYTHON_DICTDUMPER_VERSION = 0.8.4.post6
PYTHON_DICTDUMPER_SOURCE = dictdumper-$(PYTHON_DICTDUMPER_VERSION).tar.gz
PYTHON_DICTDUMPER_SITE = $(call pypi,dictdumper,dictdumper)
PYTHON_DICTDUMPER_SETUP_TYPE = setuptools
PYTHON_DICTDUMPER_LICENSE = UNKNOWN

$(eval $(python-package))
