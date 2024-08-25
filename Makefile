PYTHON=3.9
N_PROC=8
CONDA_CH=defaults conda-forge pytorch
BASENAME=$(shell basename $(CURDIR))
NVCC_USE=$(notdir $(shell which nvcc 2> NULL))

# setup
env:
	conda create -n $(BASENAME)  python=$(PYTHON)

setup:
	conda install -y --file requirements.txt $(addprefix -c ,$(CONDA_CH))
	pip install -r requirements-pip.txt  # separated for M1 chips

ifeq ($(NVCC_USE),nvcc)
	conda install -y --file requirements-gpu.txt $(addprefix -c ,$(CONDA_CH))
endif

broker:
	redis-server --protected-mode no

# services
worker:
	# auto-restart for script modifications
	PYTHONPATH=src watchmedo auto-restart \
		--directory=src/worker \
		--pattern=*.py \
		--recursive -- \
		celery -A worker.celery worker -P processes -c $(N_PROC) -l INFO

triton:
	docker run --gpus 1 --ipc host --rm -p 9000:8000 -p 9001:8001 -p 9002:8002 \
		-v $(PWD)/model_repository:/models nvcr.io/nvidia/tritonserver:24.07-py3 \
		tritonserver --model-repository=/models

api:
	PYTHONPATH=src uvicorn api.server:app --reload --host 0.0.0.0 --port 8000

dashboard:
	sh -c "./wait_for_workers.sh"
	PYTHONPATH=src celery -A worker.celery flower --port=5555

# load tests
load:
	locust -f test/ltest/locustfile.py MnistPredictionUser

load-triton:
	locust -f test/ltest/locustfile.py MnistPredictionTritonUser


# for developers
setup-dev:
	conda install --file requirements-dev.txt $(addprefix -c ,$(CONDA_CH))
	pre-commit install

format:
	black .
	isort .

lint:
	pytest src --flake8 --pylint --mypy

utest:
	PYTHONPATH=src pytest test/utest --cov=src --cov-report=html --cov-report=term --cov-config=setup.cfg

cov:
	open htmlcov/index.html
