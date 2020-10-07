ROOT := $(shell cd ..; pwd)
LANG := perl
BIN := perl
GRAMMAR := lib/Grammar.pm

BUILD_DEPS := \
    $(ROOT)/node_modules \

TEST_DEPS := \
    $(ROOT)/test/testml \
    ext-perl \

include $(ROOT)/.common.mk

export TESTML_RUN := perl-tap
export TESTML_LIB := $(ROOT)/test/suite/test:$(TESTML_LIB)
export PERL5LIB := $(ROOT)/perl/ext-perl/lib/perl5

ext-perl:
	git branch --track $@ origin/$@ 2>/dev/null || true
	git worktree add -f $@ $@

clean::
	rm -fr ext-perl
