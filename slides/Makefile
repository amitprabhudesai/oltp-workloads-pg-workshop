# Compile the slide deck
# Requires: lualatex (included in mactex-no-gui)
# Install:  brew install --cask mactex-no-gui

MAIN   = slides
ENGINE = lualatex
FLAGS  = -interaction=nonstopmode -halt-on-error

.PHONY: all clean

all: $(MAIN).pdf

$(MAIN).pdf: $(MAIN).tex
	$(ENGINE) $(FLAGS) $(MAIN).tex
	$(ENGINE) $(FLAGS) $(MAIN).tex   # second pass for page numbers

clean:
	rm -f $(MAIN).{pdf,aux,log,nav,out,snm,toc,vrb}
