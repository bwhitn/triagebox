################################################################################
#
# pdfid
#
################################################################################

PDFID_VERSION = 0.2.10
PDFID_SOURCE = pdfid_v0_2_10.zip
PDFID_SITE = https://didierstevens.com/files/software
PDFID_LICENSE = Custom
PDFID_DEPENDENCIES = python3 host-python3

define PDFID_INSTALL_TARGET_CMDS
	src_file="$$(find "$(@D)" -type f -name 'pdfid.py' | sort | head -n1)"; \
	test -n "$$src_file"; \
	mkdir -p $(TARGET_DIR)/usr/lib/triagebox-tools $(TARGET_DIR)/usr/bin; \
	$(HOST_DIR)/bin/python3 -c 'import pathlib, py_compile, sys; src = pathlib.Path(sys.argv[1]); dst = pathlib.Path(sys.argv[2]); dst.parent.mkdir(parents=True, exist_ok=True); py_compile.compile(str(src), cfile=str(dst), doraise=True, optimize=1)' \
		"$$src_file" "$(TARGET_DIR)/usr/lib/triagebox-tools/pdfid.pyc"
	printf '%s\n' \
		'#!/bin/sh' \
		'exec /usr/bin/python -O /usr/lib/triagebox-tools/pdfid.pyc "$$@"' \
		> $(TARGET_DIR)/usr/bin/pdfid
	chmod 0755 $(TARGET_DIR)/usr/bin/pdfid
	ln -sf pdfid $(TARGET_DIR)/usr/bin/pdfid.py
endef

$(eval $(generic-package))
