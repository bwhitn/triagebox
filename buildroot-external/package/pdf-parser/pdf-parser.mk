################################################################################
#
# pdf-parser
#
################################################################################

PDF_PARSER_VERSION = 0.7.13
PDF_PARSER_SOURCE = pdf-parser_V0_7_13.zip
PDF_PARSER_SITE = https://didierstevens.com/files/software
PDF_PARSER_LICENSE = Custom
PDF_PARSER_DEPENDENCIES = python3 host-python3

define PDF_PARSER_EXTRACT_CMDS
	$(UNZIP) -d $(@D) $(PDF_PARSER_DL_DIR)/$(PDF_PARSER_SOURCE)
endef

define PDF_PARSER_INSTALL_TARGET_CMDS
	src_file="$$(find "$(@D)" -type f -name 'pdf-parser.py' | sort | head -n1)"; \
	test -n "$$src_file"; \
	mkdir -p $(TARGET_DIR)/usr/lib/triagebox-tools $(TARGET_DIR)/usr/bin; \
	$(HOST_DIR)/bin/python3 -c 'import pathlib, py_compile, sys; src = pathlib.Path(sys.argv[1]); dst = pathlib.Path(sys.argv[2]); dst.parent.mkdir(parents=True, exist_ok=True); py_compile.compile(str(src), cfile=str(dst), doraise=True, optimize=1)' \
		"$$src_file" "$(TARGET_DIR)/usr/lib/triagebox-tools/pdf-parser.pyc"
	printf '%s\n' \
		'#!/bin/sh' \
		'exec /usr/bin/python -O /usr/lib/triagebox-tools/pdf-parser.pyc "$$@"' \
		> $(TARGET_DIR)/usr/bin/pdf-parser
	chmod 0755 $(TARGET_DIR)/usr/bin/pdf-parser
	ln -sf pdf-parser $(TARGET_DIR)/usr/bin/pdf-parser.py
endef

$(eval $(generic-package))
