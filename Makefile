# Mapping from long region names to shorter ones that is to be
# used in the stack names
AWS_eu-north-1_PREFIX = en1
AWS_eu-west-1_PREFIX = ew1

# Some defaults
AWS ?= aws
AWS_REGION ?= eu-north-1
AWS_PROFILE ?= default

AWS_CMD := $(AWS) --profile $(AWS_PROFILE) --region $(AWS_REGION)

STACK_REGION_PREFIX := $(AWS_$(AWS_REGION)_PREFIX)

TAGS ?= Deployment=$(STACK_REGION_PREFIX)-vpc-traffic-mirroring

define stack_template =


deploy-$(basename $(notdir $(1))): $(1)
	$(AWS_CMD) cloudformation deploy \
		--stack-name $(STACK_REGION_PREFIX)-$(basename $(notdir $(1))) \
		--tags $(TAGS) \
		--template-file $(1) \
		--capabilities CAPABILITY_NAMED_IAM

delete-$(basename $(notdir $(1))): $(1)
	$(AWS_CMD) cloudformation delete-stack \
		--stack-name $(STACK_REGION_PREFIX)-$(basename $(notdir $(1)))


endef

$(foreach template, $(wildcard templates/*.yaml), $(eval $(call stack_template,$(template))))
