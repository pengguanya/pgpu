PGPU := ./bin/pgpu
.PHONY: doctor setup build run train profile clean test
doctor:  ; $(PGPU) doctor
setup:   ; $(PGPU) setup
build:   ; $(PGPU) build
run:     ; $(PGPU) run
train:   ; $(PGPU) train
profile: ; $(PGPU) profile
clean:   ; $(PGPU) clean
test:    ; bash tests/run.sh
