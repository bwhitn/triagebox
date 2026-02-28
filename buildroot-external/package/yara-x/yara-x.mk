################################################################################
#
# yara-x
#
################################################################################

YARA_X_VERSION = 1.9.0
YARA_X_SITE = $(call github,VirusTotal,yara-x,v$(YARA_X_VERSION))
YARA_X_SUBDIR = cli
YARA_X_LICENSE = BSD-3-Clause
YARA_X_LICENSE_FILES = LICENSE
YARA_X_CARGO_BUILD_OPTS = --bin yr
YARA_X_CARGO_INSTALL_OPTS = --bin yr

define YARA_X_INSTALL_YARA_X_SYMLINK
	ln -sf yr $(TARGET_DIR)/usr/bin/yara-x
endef
YARA_X_POST_INSTALL_TARGET_HOOKS += YARA_X_INSTALL_YARA_X_SYMLINK

$(eval $(cargo-package))
