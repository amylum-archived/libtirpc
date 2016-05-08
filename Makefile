PACKAGE = libtirpc
ORG = amylum

DEP_DIR = /tmp/dep-dir

BUILD_DIR = /tmp/$(PACKAGE)-build
RELEASE_DIR = /tmp/$(PACKAGE)-release
RELEASE_FILE = /tmp/$(PACKAGE).tar.gz
PATH_FLAGS = --prefix=/usr
CONF_FLAGS =
CFLAGS = -I$(DEP_DIR)/usr/include -fPIC

PACKAGE_VERSION = $$(git --git-dir=upstream/.git describe --tags | sed 's/libtirpc-//;s/-/./g')
PATCH_VERSION = $$(cat version)
VERSION = $(PACKAGE_VERSION)-$(PATCH_VERSION)

KRB5_VERSION = 1.14.2_5
KRB5_URL = https://github.com/amylum/krb5/releases/download/$(KRB5_VERSION)/krb5.tar.gz
KRB5_TAR = /tmp/krb5.tar.gz
KRB5_DIR = /tmp/krb5
KRB5_PATH = -I$(KRB5_DIR)/usr/include -L$(KRB5_DIR)/usr/lib

.PHONY : default submodule deps manual container deps build version push local

default: submodule container

submodule:
	git submodule update --init

manual: submodule
	./meta/launch /bin/bash || true

container:
	./meta/launch

deps:
	rm -rf $(DEP_DIR)
	mkdir -p $(DEP_DIR)/usr/include/sys
	cp -R /usr/include/sys/queue.h $(DEP_DIR)/usr/include/sys/
	cp -R /usr/include/{asm,asm-generic,linux} $(DEP_DIR)/usr/include/
	rm -rf $(KRB5_DIR) $(KRB5_TAR)
	mkdir $(KRB5_DIR)
	curl -sLo $(KRB5_TAR) $(KRB5_URL)
	tar -x -C $(KRB5_DIR) -f $(KRB5_TAR)

build: submodule deps
	rm -rf $(BUILD_DIR)
	cp -R upstream $(BUILD_DIR)
	patch -d $(BUILD_DIR) -p1 < patches/nis.patch
	patch -d $(BUILD_DIR) -p1 < patches/musl-fixes.patch
	patch -d $(BUILD_DIR) -p1 < patches/add_missing_rwlock_unlocks_in_xprt_register.patch
	cd $(BUILD_DIR) && autoreconf -i
	cd $(BUILD_DIR) && CC=musl-gcc CFLAGS='$(CFLAGS) $(KRB5_PATH)' ./configure $(PATH_FLAGS) $(CONF_FLAGS)
	cd $(BUILD_DIR) && make DESTDIR=$(RELEASE_DIR) install
	mkdir -p $(RELEASE_DIR)/usr/share/licenses/$(PACKAGE)
	cp $(BUILD_DIR)/COPYING $(RELEASE_DIR)/usr/share/licenses/$(PACKAGE)/LICENSE
	cd $(RELEASE_DIR) && tar -czvf $(RELEASE_FILE) *

version:
	@echo $$(($(PATCH_VERSION) + 1)) > version

push: version
	git commit -am "$(VERSION)"
	ssh -oStrictHostKeyChecking=no git@github.com &>/dev/null || true
	git tag -f "$(VERSION)"
	git push --tags origin master
	@sleep 3
	targit -a .github -c -f $(ORG)/$(PACKAGE) $(VERSION) $(RELEASE_FILE)
	@sha512sum $(RELEASE_FILE) | cut -d' ' -f1

local: build push

