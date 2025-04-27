
SHELL = /bin/bash

help:
	@ echo "$$HELP"

define HELP

  For your PowerSchool Custom Pages convenience:

    help       This Message.
    plugin     Package the src/ directory as a plugin.


endef
export HELP

default: help

plugin: src/web_root/tps_custom/main.css
	@ mkdir -p dist
	@ rm -rf dist/ './$(plugin_name_version).zip'
	@ cp -a src dist/
	@ sed "s/version=/version=$$(git show-ref HEAD --hash)/g" \
		< web_root/tps_custom/head.html \
		> dist/web_root/tps_custom/head.html
	@ echo zip: '$(plugin_name_version).zip'
	@ cd ./dist && zip -r '$(plugin_name_version).zip' *
	@ mv './dist/$(plugin_name_version).zip' './dist/$(plugin_name_version).zip'
	@ rm -rf dist
	