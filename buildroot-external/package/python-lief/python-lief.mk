################################################################################
#
# python-lief
#
################################################################################

PYTHON_LIEF_VERSION = 0.17.3
PYTHON_LIEF_SOURCE = lief-0.17.3.tar.gz
PYTHON_LIEF_SITE = https://files.pythonhosted.org/packages/ea/7d/ba1b4e896712f5c161a6ef6eb546aaaecacf10f7c0ae8890b74359c62655
PYTHON_LIEF_SETUP_TYPE = pep517
PYTHON_LIEF_LICENSE = Apache License 2.0

$(eval $(python-package))
