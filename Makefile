.PHONY: app install icon clean

app:
	./scripts/build-app.sh

install:
	./scripts/build-app.sh --install

icon:
	swift scripts/make-icon.swift Resources/AppIcon.icns

clean:
	rm -rf .build build
