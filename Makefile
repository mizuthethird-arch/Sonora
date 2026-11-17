.PHONY: doctor check-databases

doctor:
	./scripts/doctor.sh

check-databases:
	./scripts/check-module-databases.sh
