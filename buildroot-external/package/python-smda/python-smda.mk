################################################################################
#
# python-smda
#
################################################################################

PYTHON_SMDA_VERSION = 1.14.3
PYTHON_SMDA_SOURCE = smda-1.14.3.tar.gz
PYTHON_SMDA_SITE = https://files.pythonhosted.org/packages/a8/13/ae12a70cdc7c695ce94c3898940f235ea6edd593d49ffa8acbc5538b34cf
PYTHON_SMDA_SETUP_TYPE = setuptools
PYTHON_SMDA_LICENSE = BSD 2-Clause

$(eval $(python-package))
