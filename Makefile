.PHONY: install test lint api mcp train local local-down validate

install:
	python -m pip install -e '.[dev,mcp,ml]'

test:
	pytest -q

lint:
	ruff check src tests training

api:
	uvicorn aioffice.main:app --reload --port 8000

mcp:
	python -m aioffice.mcp_server

train:
	python training/train_candidates.py

local:
	./build.sh --local

local-down:
	./build.sh --local --destroy

validate:
	bash -n build.sh
	python -m compileall -q src services training tests
