%% Requirements-led model + verification matrix
% Aircraft Cabin Pressurisation System (self-contained)

clear; clc; close all;
rng(42); % reproducibility

%% ==========================================================
%  SECTION A — REQUIREMENTS
%  ==========================================================
REQ = table( ...
    ["REQ-01"; "REQ-02"; "REQ-03"; "REQ-04"], ...
    ["The cabin pressurisation system shall reach CRUISE mode within 900 seconds."; ...
     "The cabin pressurisation system shall end in CRUISE mode under nominal conditions."; ...
     "The system shall declare FAULT if cruise conditions are not achieved within the timeout."; ...
     "The differential pressure shall not exceed 8.5 psi under nominal conditions."], ...
    ["TimeToCruise_sec"; "IsCruise"; "FaultOnTimeout"; "MaxDiffPressureSafe"], ...
    ["<="; "=="; "=="; "=="], ...
    [900; 1; 0; 1], ...
    ["SingleRun"; "SingleRun"; "SingleRun"; "SingleRun"], ...
    ["Cruise conditions must be reached within an acceptable time."; ...
     "Nominal scenario should end in CRUISE."; ...
     "Timeout should not occur in the nominal case."; ...
     "Pressure differential must remain within safety limits."], ...
    'VariableNames', {'ID','Statement','Metric','Operator','Threshold','Scope','Notes'} ...
);

%% ==========================================================
%  SECTION B — MODEL PARAMETERS
%  ==========================================================
SCEN.name = "Nominal Cabin Pressurisation Design";

% Aircraft profile
SCEN.takeoffAltitude_ft = 1000;          
SCEN.cruiseAircraftAlt_ft = 35000;       
SCEN.aircraftClimbRate_ftps = 50;        

% Cabin pressurisation behaviour
SCEN.initialCabinAlt_ft = 0;             
SCEN.targetCabinAlt_ft = 8000;           
SCEN.cabinClimbRate_ftps = 10;           

% Safety / logic
SCEN.maxDiffPressure_psi = 8.5;          
SCEN.psiPerFt = 0.00025;                 
SCEN.timeout_sec = 900;                  

% Variability controls (Week 3: deterministic)
SCEN.stdAircraftClimbRate_ftps = 0.0;
SCEN.stdCabinClimbRate_ftps = 0.0;

% Fault settings
SCEN.sensorFault = false;                
SCEN.pRandomFailurePerSec = 0.0;         

%% ==========================================================
%  SECTION C — SIMULATION SETTINGS
%  ==========================================================
SIM.N = 5;
SIM.dt = 1.0;            
SIM.maxTime_sec = 1200;