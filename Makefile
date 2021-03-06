COVERAGE_REPORT=coverage
HTML_DIR=build/html
LATEX_DIR=build/latex
WWW_DIR=build/website
DOCSRC_DIR=doc

#
# Determine details on the Python/system
#

PYVER := $(shell python -V 2>&1 | cut -d ' ' -f 2,2 | cut -d '.' -f 1,2)
DISTUTILS_PLATFORM := \
	$(shell \
		python -c "import distutils.util; print distutils.util.get_platform()")

#
# Building
#

all: build

# build included 3rd party pieces (if present)
cn_3rd: cn_3rd-stamp
cn_3rd-stamp:
	find 3rd -mindepth 1 -maxdepth 1  -type d | \
	 while read d; do \
	  [ -f "$$d/Makefile" ] && $(MAKE) -C "$$d"; \
     done
	touch $@


cn_build: cn_build-stamp
cn_build-stamp: cn_3rd
	python setup_cnifti.py config --noisy
	python setup_cnifti.py build_ext
	python setup_cnifti.py build_py
	# to overcome the issue of not-installed _clib.so
	ln -sf ../build/lib.$(DISTUTILS_PLATFORM)-$(PYVER)/cnifti/_clib.so cnifti/
	ln -sf ../build/src.$(DISTUTILS_PLATFORM)-$(PYVER)/cnifti/clib.py cnifti/
	touch $@

build: 
	python setup.py config --noisy
	python setup.py build


#
# Cleaning
#

clean:
	-rm -rf build
	-rm *-stamp
	-rm cnifti/clib.py cnifti/_clib.so
	find 3rd -mindepth 2 -maxdepth 2  -type f -name '*-stamp' | xargs -L10 rm -f

distclean: clean
	-rm MANIFEST
	-rm $(COVERAGE_REPORT)
	@find . -name '*.py[co]' \
		 -o -name '*.a' \
		 -o -name '*,cover' \
		 -o -name '.coverage' \
		 -o -iname '*~' \
		 -o -iname '*.kcache' \
		 -o -iname '*.pstats' \
		 -o -iname '*.prof' \
		 -o -iname '#*#' | xargs -L10 rm -f
	-rm -r dist
	-rm build-stamp apidoc-stamp
#	-rm tests/data/*.hdr.* tests/data/*.img.* tests/data/something.nii \
#		tests/data/noise* tests/data/None.nii


#
# Little helpers
#

$(WWW_DIR):
	if [ ! -d $(WWW_DIR) ]; then mkdir -p $(WWW_DIR); fi


#
# Tests
#

test: unittest testmanual


ut-%: build
	@PYTHONPATH=.:$(PYTHONPATH) nosetests nifti/tests/test_$*.py


unittest: build cn_build
	@PYTHONPATH=.:$(PYTHONPATH) nosetests nifti --with-doctest
	nosetests cnifti --with-doctest

testmanual: build cn_build
# go into data, because docs assume now data dir
	@PYTHONPATH=.:$(PYTHONPATH) nosetests --with-doctest --doctest-extension=.txt doc


coverage: build
	@PYTHONPATH=.:$(PYTHONPATH) nosetests --with-coverage


#
# Documentation
#

htmldoc: build
	cd $(DOCSRC_DIR) && PYTHONPATH=$(CURDIR) $(MAKE) html


pdfdoc: build
	cd $(DOCSRC_DIR) && PYTHONPATH=$(CURDIR) $(MAKE) latex
	cd $(LATEX_DIR) && $(MAKE) all-pdf


#
# Website
#

website: website-stamp
website-stamp: $(WWW_DIR) htmldoc pdfdoc
	cp -r $(HTML_DIR)/* $(WWW_DIR)
	cp $(LATEX_DIR)/*.pdf $(WWW_DIR)
	touch $@


upload-website: website
	rsync -rzhvp --delete --chmod=Dg+s,g+rw $(WWW_DIR)/* \
		web.sourceforge.net:/home/groups/n/ni/niftilib/htdocs/pynifti/

#
# Sources
#

pylint: distclean
	# do distclean first to silence SWIG's sins
	pylint --rcfile doc/misc/pylintrc nifti


#
# Distributions
#

# we need to build first to be able to update the manpage
orig-src: build
	# clean existing dist dir first to have a single source tarball to process
	-rm -rf dist
	# update manpages
	PYTHONPATH=. help2man -N -n "compute peristimulus timeseries of fMRI data" \
		bin/pynifti_pst > man/pynifti_pst.1
	# now clean
	$(MAKE) distclean
	# check versions
	grep -iR 'version[ ]*[=:]' * | python tools/checkversion.py
	# let python create the source tarball
	python setup.py sdist --formats=gztar
	# rename to proper Debian orig source tarball and move upwards
	# to keep it out of the Debian diff
	file=$$(ls -1 dist); \
		ver=$${file%*.tar.gz}; \
		ver=$${ver#pynifti-*}; \
		mv dist/$$file ../pynifti_$$ver.tar.gz


bdist_rpm: 3rd
	python setup.py bdist_rpm \
	  --doc-files "doc" \
	  --packager "Michael Hanke <michael.hanke@gmail.com>" \
	  --vendor "Michael Hanke <michael.hanke@gmail.com>"


# build MacOS installer -- depends on patched bdist_mpkg for Leopard
bdist_mpkg: 3rd
	python tools/mpkg_wrapper.py setup.py build_ext
	python tools/mpkg_wrapper.py setup.py install


.PHONY: orig-src pylint apidoc
