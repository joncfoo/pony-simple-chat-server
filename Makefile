.PHONY: watch run build

watch:
	find ./main.pony | entr -cr make run

run: build
	./main

build:
	docker run --rm -v $(shell pwd):/src/main ponylang/ponyc:release
