MANIFESTS_DIR=manifests
VENDOR_DIR=jsonnet/vendor

$(MANIFESTS_DIR): $(VENDOR_DIR) jsonnet/main.jsonnet $(shell find jsonnet/lib/ -type f '(' -name '*.jsonnet' -o -name '*.json' -o -name '*.libsonnet' ')' -type f) $(shell find jsonnet/lib/ -type d)
	rm -rf $(MANIFESTS_DIR)
	mkdir -p $(MANIFESTS_DIR)
	jsonnet -J $(VENDOR_DIR) -c -m $(MANIFESTS_DIR) -S jsonnet/main.jsonnet
	$(MAKE) beautify

$(VENDOR_DIR): jsonnet/jsonnetfile.json jsonnet/jsonnetfile.lock.json
	cd jsonnet && jb install

.PHONY: beautify
beautify:
	for i in $(shell find $(MANIFESTS_DIR)/ -name '*.yaml'); do yq --prettyPrint --no-colors --inplace $$i; done

.PHONY: clean
clean:
	rm -rf $(VENDOR_DIR)

.PHONY: update
update:
	cd jsonnet && jb update
	rm -rf $(VENDOR_DIR)
	$(MAKE) generate
