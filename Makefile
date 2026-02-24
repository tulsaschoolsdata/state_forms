SHELL = /bin/bash

INSECURE = $(shell echo ${PS_HOST} | grep -q '://[0-9.]\+' && echo '--insecure')
export COOKIES ?= .cookies
export CURL ?= curl $(INSECURE) -b $(COOKIES) -c $(COOKIES)

PS_ENV ?= $(shell echo $(PS_HOST) | cut -d'/' -f3)
PS_VERSION = $(shell $(CURL) -s "$(PS_HOST)/admin/systemsettings/serverstats.html" | grep -o 'powerschool-core-\([0-9.]\+\)' | cut -d'-' -f3)
SESSION_STATUS_CODE = $(shell $(CURL) -o /dev/null -s -w "%{http_code}" "$(PS_HOST)/admin/home.html")
STAMP ?= $(shell date '+%Y%m%d%H%M%S')

plugin_version ?= $(shell grep '<plugin' src/plugin.xml | sed 's:.*version="::;s:">::')
plugin_name ?= ok_state_forms
plugin_name_version = $(plugin_name)-v$(plugin_version)

help:
	@ echo "$$HELP"

define HELP

  For your PowerSchool Custom Pages convenience:

    help       This Message.
    plugin     Package the src/ directory as a plugin.


endef
export HELP

default: help

plugin: src/web_root/
	@ echo "Plugin version: $(plugin_version)"
	@ echo "Plugin name: $(plugin_name)"
	@ echo "Plugin name version: $(plugin_name_version)"
	@ mkdir -p dist
	@ rm -rf dist/ './$(plugin_name_version).zip'
	@ cp -a src dist/
	@ if [ -f src/web_root/head.html ]; then \
        sed "s/version=/version=$$(git show-ref HEAD --hash)/g" \
            < src/web_root/head.html \
            > dist/web_root/head.html; \
    fi
	@ echo zip: '$(plugin_name_version).zip'
	@ cd ./dist && zip -r '../$(plugin_name_version).zip' *
	@ rm -rf dist
