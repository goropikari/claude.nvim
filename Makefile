DEV_DIR := $(CURDIR)/.dev
SNACKS  := $(DEV_DIR)/snacks.nvim
TERMS   := $(DEV_DIR)/terminals.nvim
PLENARY := $(DEV_DIR)/plenary.nvim

.PHONY: all dev test clean-dev fmt fmt-check

all:
	chmod +x scripts/hook.sh

# Launch Neovim with only the required plugins, no plugin manager.
# Dependencies are cloned into .dev/ on first run.
dev: $(SNACKS) $(TERMS)
	nvim -u dev/init.lua

# Run the test suite headlessly.
test: $(PLENARY)
	nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua',sequential=true}"

$(SNACKS):
	git clone --filter=blob:none --depth=1 https://github.com/folke/snacks.nvim $@

$(TERMS):
	git clone --filter=blob:none --depth=1 https://github.com/goropikari/terminals.nvim $@

$(PLENARY):
	git clone --filter=blob:none --depth=1 https://github.com/nvim-lua/plenary.nvim $@

# Remove cloned dependencies.
clean-dev:
	rm -rf $(DEV_DIR)

# Format all source files.
fmt:
	stylua lua/ plugin/ dev/
	dprint fmt

# Check formatting without modifying files (useful for CI).
fmt-check:
	stylua --check lua/ plugin/ dev/
	dprint check
