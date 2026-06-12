.PHONY: render

render:  ## Preview PyPI long description rendering
	pip install -q "readme_renderer[md]" 2>/dev/null
	python -m readme_renderer README.md > /tmp/handoff-pypi-preview.html
	@echo "✅  /tmp/handoff-pypi-preview.html  ($(shell wc -c < /tmp/handoff-pypi-preview.html | tr -d ' ') bytes)"
	open /tmp/handoff-pypi-preview.html
