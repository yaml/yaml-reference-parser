ROOT := $(shell cd ..; pwd)

include $(ROOT)/.common.mk

ALL := \
    testml \
    yaml-test-suite.tml \

all: $(ALL)

clean::
	rm -fr $(ALL)
	rm -fr .testml
	rm -fr suite

testml:
	$(call git-clone,$@,$(TESTML_REPO),$(TESTML_COMMIT))
	git -C $@ fetch origin ext/perl node_modules
	$(MAKE) -C $@ ext/perl
	$(MAKE) -C $@ src/node_modules

yaml-test-suite.tml: suite
	for file in $</testml/*.tml; do \
	  line=$$(head -n1 "$$file"); \
	  line=$${line/===/%Import}; \
	  line=$${line/-/"    # "}; \
	  echo "$$line"; \
	done > $@

suite:
	$(call git-clone,$@,$(YAML_TEST_SUITE_REPO),$(YAML_TEST_SUITE_COMMIT))
	$(MAKE) -C $@ testml
	ln -s testml $@/test
