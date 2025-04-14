MANIFESTS_DIR=manifests
VENDOR_DIR=jsonnet/vendor

.PHONY: generate
generate: $(MANIFESTS_DIR) $(VENDOR_DIR)
	jsonnet -J $(VENDOR_DIR) -c -m $(MANIFESTS_DIR) -S jsonnet/main.jsonnet
	$(MAKE) beautify

$(MANIFESTS_DIR):
	rm -rf $(MANIFESTS_DIR)
	mkdir -p $(MANIFESTS_DIR)

$(VENDOR_DIR):
	jb install

.PHONY: beautify
beautify:
	for i in $(shell find $(MANIFESTS_DIR)/ -name '*.yaml'); do yq --prettyPrint --no-colors --inplace $$i; done

.PHONY: clean
clean:
	rm -rf vendor

.PHONY: update
update:
	jb update
	rm -rf $(VENDOR_DIR)
	$(MAKE) generate
