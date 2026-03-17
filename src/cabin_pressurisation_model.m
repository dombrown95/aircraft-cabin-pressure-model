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

%% ==========================================================
%  SECTION D — RUN SIMULATION
%  ==========================================================
out = runSimulation(SCEN, SIM);

evidence = struct();
evidence.TimeToCruise_sec = out.timeToCruise_sec(end);
evidence.IsCruise = double(out.isCruise(end));
evidence.FaultOnTimeout = double(out.faultOnTimeout(end));
evidence.MaxDiffPressureSafe = double(out.maxDiffPressure_psi(end) <= SCEN.maxDiffPressure_psi);

%% ==========================================================
%  SECTION E — VERIFY REQUIREMENTS
%  ==========================================================
V = verifyRequirements(REQ, evidence);

disp("=== Evidence ===");
disp(struct2table(evidence));
disp("=== Verification Matrix ===");
disp(V);

%% ==========================================================
%  Local Functions
%  ==========================================================

function out = runSimulation(scen, SIM)
    N = SIM.N;
    out.timeToCruise_sec = nan(N,1);
    out.isCruise = false(N,1);
    out.faultOnTimeout = false(N,1);
    out.maxDiffPressure_psi = nan(N,1);

    for i = 1:N
        [out.isCruise(i), out.timeToCruise_sec(i), out.faultOnTimeout(i), out.maxDiffPressure_psi(i)] = ...
            simulateOneRun(scen, SIM.dt, SIM.maxTime_sec);
    end
end

function [isCruise, timeToCruise_sec, faultOnTimeout, maxDiffPressure_psi] = simulateOneRun(scen, dt, maxTime_sec)

    state = "GROUND";
    t = 0;

    aircraftAlt_ft = 0;
    cabinAlt_ft = scen.initialCabinAlt_ft;

    faultOnTimeout = false;
    maxDiffPressure_psi = 0;

    % Draw uncertain parameters
    aircraftClimbRate = max(1, scen.aircraftClimbRate_ftps + randn * scen.stdAircraftClimbRate_ftps);
    cabinClimbRate = max(1, scen.cabinClimbRate_ftps + randn * scen.stdCabinClimbRate_ftps);

    while t < maxTime_sec
        % Random fault hazard
        if rand < scen.pRandomFailurePerSec * dt
            state = "FAULT";
            break;
        end

        % Sensor fault
        if scen.sensorFault
            state = "FAULT";
            break;
        end

        % Aircraft climbs until cruise altitude
        if aircraftAlt_ft < scen.cruiseAircraftAlt_ft
            aircraftAlt_ft = aircraftAlt_ft + aircraftClimbRate * dt;
        end

        % Calculate differential pressure (simplified)
        diffPressure_psi = max(0, (aircraftAlt_ft - cabinAlt_ft) * scen.psiPerFt);
        maxDiffPressure_psi = max(maxDiffPressure_psi, diffPressure_psi);

        switch state
            case "GROUND"
                if aircraftAlt_ft >= scen.takeoffAltitude_ft
                    state = "PRESSURISING";
                end

            case "PRESSURISING"
                if cabinAlt_ft < scen.targetCabinAlt_ft
                    cabinAlt_ft = cabinAlt_ft + cabinClimbRate * dt;
                end

                if diffPressure_psi > scen.maxDiffPressure_psi
                    state = "FAULT";
                    break;
                end

                if aircraftAlt_ft >= scen.cruiseAircraftAlt_ft && ...
                   abs(cabinAlt_ft - scen.targetCabinAlt_ft) <= 100
                    state = "CRUISE";
                    break;
                end

                if t >= scen.timeout_sec
                    state = "FAULT";
                    faultOnTimeout = true;
                    break;
                end

            case "CRUISE"
                break;

            case "FAULT"
                break;
        end

        t = t + dt;
    end

    isCruise = (state == "CRUISE");
    timeToCruise_sec = t;
end

function V = verifyRequirements(REQ, evidence)
    n = height(REQ);

    Observed = strings(n,1);
    Pass = false(n,1);

    for i = 1:n
        metricName = REQ.Metric{i};

        if ~isfield(evidence, metricName)
            Observed(i) = "MISSING_METRIC";
            Pass(i) = false;
            continue;
        end

        obs = evidence.(metricName);
        Observed(i) = string(obs);

        op = REQ.Operator{i};
        thr = REQ.Threshold(i);

        switch op
            case "<="
                Pass(i) = (obs <= thr);
            case "<"
                Pass(i) = (obs < thr);
            case ">="
                Pass(i) = (obs >= thr);
            case ">"
                Pass(i) = (obs > thr);
            case "=="
                Pass(i) = (obs == thr);
            otherwise
                Pass(i) = false;
        end
    end

    V = table(REQ.ID, REQ.Statement, REQ.Metric, Observed, REQ.Operator, REQ.Threshold, Pass, REQ.Scope, REQ.Notes, ...
        'VariableNames', {'ReqID','Statement','Metric','Observed','Operator','Threshold','Pass','Scope','Notes'});
end