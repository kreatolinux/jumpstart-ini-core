PREFIX ?= /usr
DESTDIR ?=
COREDIR = $(DESTDIR)$(PREFIX)/lib/jumpstart/cores/ini

.PHONY: install test

install:
	install -d $(COREDIR)
	cp -R init.kg bin share $(COREDIR)/

test:
	nim c -r tests/test_core.nim
