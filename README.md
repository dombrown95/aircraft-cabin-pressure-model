# Aircraft Cabin Pressurisation System (Requirements-Led Model)

## Overview
This project implements a requirements-led simulation and verification model of an aircraft cabin pressurisation system using MATLAB. The system models altitude changes, cabin pressurisation behaviour and safety logic, evaluating system performance against defined requirements.

**The model demonstrates:**
- Requirements traceability
- State-based system behaviour
- Verification using a structured matrix
- Scenario-based testing and Monte Carlo analysis

## System Behaviour
### States
| State	| Description |
|-------|-------------|
| GROUND |	Aircraft below takeoff altitude  |
|PRESSURISING  |  Cabin altitude adjusting during climb  |
|CRUISE	|  Stable cruise conditions achieved  |
|FAULT	|  Safety or system fault detected  |

### Key Transitions
GROUND → PRESSURISING
- Trigger: Aircraft altitude ≥ takeoff altitude
  
PRESSURISING → CRUISE
- Trigger:
    - Aircraft at cruise altitude
    - Cabin altitude within tolerance (±100 ft)

PRESSURISING → FAULT
- Trigger:
    - Sensor fault detected (REQ-04 / REQ-06)
    - Differential pressure exceeds limit (REQ-03)

Timeout Detection (no transition by default)
- Trigger: Cruise not achieved within 750 seconds (REQ-05)
- Behaviour: Sets TimeoutDetected = true (no forced FAULT unless enabled)

## Requirements Summary
|ID|	    Description|
|---|----|
|REQ-01|	Reach CRUISE within 750 seconds|
|REQ-02|	End in CRUISE under nominal conditions|
|REQ-03|	Do not exceed maximum differential pressure|
|REQ-04|	Detect and flag sensor fault|
|REQ-05|	Detect timeout if CRUISE not reached|
|REQ-06|	Transition to FAULT on sensor fault|

## Running the model
The model can be run in MATLAB by clicking the 'Run' button or using the console command run('cabin_pressurisation_model.m')

## Monte Carlo Analysis
The Monte Carlo simulation runs automatically when enabled:</br></br>
```MC.enabled = true;```
</br></br>Outputs:
- Mean time to cruise
- Pass rate (%)
- Timeout rate (%)
- Distribution plot with requirement threshold

## Future Improvements
- Integrate full Simulink/Stateflow execution with MATLAB verification
- Add redundancy and fault-tolerant logic
- Model sensor noise and failure modes more realistically
- Extend to multi-zone cabin pressurisation
- Incorporate certification-style traceability (e.g. DO-178C artefacts)