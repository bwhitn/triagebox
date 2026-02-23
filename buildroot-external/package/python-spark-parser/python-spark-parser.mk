################################################################################
#
# python-spark-parser
#
################################################################################

PYTHON_SPARK_PARSER_VERSION = 1.9.0
PYTHON_SPARK_PARSER_SOURCE = spark_parser-$(PYTHON_SPARK_PARSER_VERSION).tar.gz
PYTHON_SPARK_PARSER_SITE = https://files.pythonhosted.org/packages/3c/e1/a443990c6c32cb7fa7d3896405d2924c4921c74c1ffd5b90ffaeb42f778a
PYTHON_SPARK_PARSER_SETUP_TYPE = setuptools
PYTHON_SPARK_PARSER_LICENSE = UNKNOWN

$(eval $(python-package))
