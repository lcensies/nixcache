INVENTORY ?= inventory.ini
PLAYBOOK  ?= playbook.yml
TAGS      ?=
LIMIT     ?=

ANSIBLE_ARGS :=
ifdef TAGS
  ANSIBLE_ARGS += --tags $(TAGS)
endif
ifdef LIMIT
  ANSIBLE_ARGS += --limit $(LIMIT)
endif

.PHONY: deploy requirements lint check

deploy:
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) $(ANSIBLE_ARGS)

requirements:
	ansible-galaxy install -r requirements.yml

lint:
	ansible-lint $(PLAYBOOK)

check:
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --check $(ANSIBLE_ARGS)
