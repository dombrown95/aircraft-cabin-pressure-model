%% Requirements-led model + verification matrix
% Aircraft Cabin Pressurisation System (self-contained)

clear; clc; close all;
rng(42); % reproducibility

%% ==========================================================
%  SECTION A — REQUIREMENTS
%  ==========================================================
REQ = table( ...
    ["REQ-01"; "REQ-02"; "REQ-03"; "REQ-04"; "REQ-05"], ...
    ["The cabin pressurisation system shall reach CRUISE mode within 900 seconds."; ...
     "The cabin pressurisation system shall end in CRUISE mode under nominal conditions."; ...
     "The system shall not exceed the maximum differential pressure limit under nominal conditions."; ...
     "The system shall declare FAULT when sensor data is unavailable."; ...
     "The system shall declare FAULT if cruise conditions are not achieved within the timeout."], ...
    ["TimeToCruise_sec"; "IsCruise"; "MaxDiffPressureSafe"; "SensorFaultDetected"; "FaultOnTimeout"], ...
    ["<="; "=="; "=="; "=="; "=="], ...
    [900; 1; 1; 1; 1], ...
    ["SingleRun"; "SingleRun"; "SingleRun"; "SingleRun"; "SingleRun"], ...
    ["Performance"; "Functional"; "Safety"; "Fault handling"; "Timeout protection"], ...
    'VariableNames', {'ID','Statement','Metric','Operator','Threshold','Scope','Notes'} ...
);

%% ==========================================================
%  SECTION B — MODEL PARAMETERS
%  ==========================================================
SCEN.name = "Nominal Cabin Pressurisation Design";

% Aircraft profile
SCEN.takeoffAltitude_ft = 1000;          % above this, aircraft is considered airborne
SCEN.cruiseAircraftAlt_ft = 35000;       % target aircraft altitude
SCEN.aircraftClimbRate_ftps = 50;        % aircraft climb rate (ft/s)

% Cabin pressurisation behaviour
SCEN.initialCabinAlt_ft = 0;             % starting cabin altitude
SCEN.targetCabinAlt_ft = 8000;           % cabin altitude at cruise
SCEN.cabinClimbRate_ftps = 10;           % cabin altitude changes more slowly than aircraft altitude

% Safety / logic
SCEN.maxDiffPressure_psi = 8.5;          % maximum allowable differential pressure
SCEN.psiPerFt = 0.00025;                 % simplified conversion from altitude difference to psi
SCEN.timeout_sec = 900;                  % timeout for reaching cruise mode

% Variability controls (deterministic)
SCEN.stdAircraftClimbRate_ftps = 0.0;
SCEN.stdCabinClimbRate_ftps = 0.0;

% Fault settings
SCEN.sensorFault = false;                % nominal run = false
SCEN.pRandomFailurePerSec = 0.0;         % nominal run = 0

%% ==========================================================
%  SECTION C — SIMULATION SETTINGS
%  ==========================================================
SIM.N = 5;
SIM.dt = 1.0;            % seconds
SIM.maxTime_sec = 1200;  % simulation cap

%% ==========================================================
%  SECTION D — RUN SCENARIOS
%  ==========================================================
for scen_id = 1:4

    SCEN_CASE = SCEN;
    SCEN_CASE.id = scen_id;

    switch scen_id
        case 1
            SCEN_CASE.name = "SCEN-01: Normal Operation";
            SCEN_CASE.sensorFault = false;
            SCEN_CASE.cabinClimbRate_ftps = 10;
            SCEN_CASE.maxDiffPressure_psi = 8.5;

        case 2
            SCEN_CASE.name = "SCEN-02: Sensor Fault";
            SCEN_CASE.sensorFault = true;

        case 3
            SCEN_CASE.name = "SCEN-03: Slow Cabin Response";
            SCEN_CASE.sensorFault = false;
            SCEN_CASE.cabinClimbRate_ftps = 4;

        case 4
            SCEN_CASE.name = "SCEN-04: Reduced Pressure Limit";
            SCEN_CASE.sensorFault = false;
            SCEN_CASE.maxDiffPressure_psi = 5.0;
    end

    out = runSimulation(SCEN_CASE, SIM);

    evidence = struct();
    evidence.TimeToCruise_sec = out.timeToCruise_sec(end);
    evidence.IsCruise = double(out.isCruise(end));
    evidence.FaultOnTimeout = double(out.faultOnTimeout(end));
    evidence.MaxDiffPressureSafe = double(out.maxDiffPressure_psi(end) <= SCEN_CASE.maxDiffPressure_psi);
    evidence.SensorFaultDetected = double(SCEN_CASE.sensorFault && ~out.isCruise(end));

    %% ==========================================================
    %  SECTION E — VERIFY REQUIREMENTS
    %  ==========================================================
    V = verifyRequirements(REQ, evidence);

    disp("==========================================================");
    disp(SCEN_CASE.name);
    disp("==========================================================");
    disp("=== Evidence (Simulation Output) ===");
    disp(struct2table(evidence));
    disp("=== Verification Matrix ===");
    disp(V);

        figure('Name', sprintf('Simulation Results - %s', SCEN_CASE.name), ...
           'Position', [100+(scen_id*40), 100+(scen_id*40), 1000, 450]);

    subplot(2,2,1);
    plot(out.timeLog, out.aircraftAltLog, 'LineWidth', 1.5); hold on;
    plot(out.timeLog, out.cabinAltLog, 'LineWidth', 1.5);
    xlabel('Time (sec)');
    ylabel('Altitude (ft)');
    title(sprintf('Altitude Profile (%s)', SCEN_CASE.name));
    legend('Aircraft Altitude', 'Cabin Altitude', 'Location', 'northwest');
    grid on;

    subplot(2,2,3);
    plot(out.timeLog, out.diffPressureLog, 'LineWidth', 1.5); hold on;
    yline(SCEN_CASE.maxDiffPressure_psi, '--', 'Pressure Limit');
    xlabel('Time (sec)');
    ylabel('Differential Pressure (psi)');
    title('Differential Pressure');
    grid on;

    subplot(2,2,[2 4]);
    stateNumeric = zeros(size(out.stateLog));
    stateNumeric(out.stateLog == "GROUND") = 0;
    stateNumeric(out.stateLog == "PRESSURISING") = 1;
    stateNumeric(out.stateLog == "CRUISE") = 2;
    stateNumeric(out.stateLog == "FAULT") = 3;

    plot(out.timeLog, stateNumeric, 'LineWidth', 2);
    yticks([0 1 2 3]);
    yticklabels({'GROUND','PRESSURISING','CRUISE','FAULT'});
    xlabel('Time (sec)');
    title('State Transitions');
    ylim([-0.5 3.5]);
    grid on;

    fprintf("\n--- Scenario Summary ---\n");
    fprintf("Scenario: %s\n", SCEN_CASE.name);
    fprintf("TimeToCruise_sec: %.2f\n", evidence.TimeToCruise_sec);
    fprintf("IsCruise: %d | FaultOnTimeout: %d | MaxDiffPressureSafe: %d | SensorFaultDetected: %d\n\n", ...
        evidence.IsCruise, evidence.FaultOnTimeout, evidence.MaxDiffPressureSafe, evidence.SensorFaultDetected);

end

%% ==========================================================
%  SECTION F — PLOTS
%  ==========================================================
figure;
plot(out.timeToCruise_sec, '-o');
xlabel('Run #');
ylabel('Time To Cruise (sec)');
title('Time to Reach Cruise Mode Across Runs');

figure;
bar(out.isCruise);
xlabel('Run #');
ylabel('IsCruise (1=true)');
title('End State CRUISE Across Runs');

figure;
plot(out.maxDiffPressure_psi, '-o');
xlabel('Run #');
ylabel('Maximum Differential Pressure (psi)');
title('Maximum Differential Pressure Across Runs');

%% ==========================================================
%  OPTIONAL MINI REPORT
%  ==========================================================
fprintf("\n--- Mini MBSE Report ---\n");
fprintf("Scenario: %s\n", SCEN.name);
fprintf("Runs: %d | dt: %.2f sec\n", SIM.N, SIM.dt);
fprintf("Example evidence used for verification: last run\n");
fprintf("TimeToCruise_sec: %.2f | IsCruise: %d | FaultOnTimeout: %d | MaxDiffPressureSafe: %d\n", ...
    evidence.TimeToCruise_sec, evidence.IsCruise, evidence.FaultOnTimeout, evidence.MaxDiffPressureSafe);

%% ==========================================================
%  Local Functions
%  ==========================================================

function out = runSimulation(scen, SIM)
    N = SIM.N;
    out.timeToCruise_sec = nan(N,1);
    out.isCruise = false(N,1);
    out.faultOnTimeout = false(N,1);
    out.maxDiffPressure_psi = nan(N,1);

    % Keep final run logs for plotting
    out.timeLog = [];
    out.aircraftAltLog = [];
    out.cabinAltLog = [];
    out.diffPressureLog = [];
    out.stateLog = [];

    for i = 1:N
        [out.isCruise(i), out.timeToCruise_sec(i), out.faultOnTimeout(i), ...
         out.maxDiffPressure_psi(i), timeLog, aircraftAltLog, cabinAltLog, ...
         diffPressureLog, stateLog] = simulateOneRun(scen, SIM.dt, SIM.maxTime_sec);

        if i == N
            out.timeLog = timeLog;
            out.aircraftAltLog = aircraftAltLog;
            out.cabinAltLog = cabinAltLog;
            out.diffPressureLog = diffPressureLog;
            out.stateLog = stateLog;
        end
    end
end

function [isCruise, timeToCruise_sec, faultOnTimeout, maxDiffPressure_psi, ...
          timeLog, aircraftAltLog, cabinAltLog, diffPressureLog, stateLog] = ...
          simulateOneRun(scen, dt, maxTime_sec)

    state = "GROUND";
    t = 0;

    aircraftAlt_ft = 0;
    cabinAlt_ft = scen.initialCabinAlt_ft;

    faultOnTimeout = false;
    maxDiffPressure_psi = 0;

    % Draw uncertain parameters
    aircraftClimbRate = max(1, scen.aircraftClimbRate_ftps + randn * scen.stdAircraftClimbRate_ftps);
    cabinClimbRate = max(1, scen.cabinClimbRate_ftps + randn * scen.stdCabinClimbRate_ftps);

    steps = floor(maxTime_sec / dt) + 1;
    timeLog = zeros(steps,1);
    aircraftAltLog = zeros(steps,1);
    cabinAltLog = zeros(steps,1);
    diffPressureLog = zeros(steps,1);
    stateLog = strings(steps,1);

    idx = 1;

    while t < maxTime_sec
        % Random fault hazard  
        if rand < scen.pRandomFailurePerSec * dt
            state = "FAULT";
        end

        % Sensor fault
        if scen.sensorFault
            state = "FAULT";
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
                % Cabin altitude rises more slowly than aircraft altitude
                if cabinAlt_ft < scen.targetCabinAlt_ft
                    cabinAlt_ft = cabinAlt_ft + cabinClimbRate * dt;
                end

                % Safety check
                if diffPressure_psi > scen.maxDiffPressure_psi
                    state = "FAULT";
                % Cruise condition
                elseif aircraftAlt_ft >= scen.cruiseAircraftAlt_ft && ...
                       abs(cabinAlt_ft - scen.targetCabinAlt_ft) <= 100
                    state = "CRUISE";
                % Timeout condition
                elseif t >= scen.timeout_sec
                    state = "FAULT";
                    faultOnTimeout = true;
                end

            case "CRUISE"
                % Hold state

            case "FAULT"
                % Hold state
        end

        timeLog(idx) = t;
        aircraftAltLog(idx) = aircraftAlt_ft;
        cabinAltLog(idx) = cabinAlt_ft;
        diffPressureLog(idx) = diffPressure_psi;
        stateLog(idx) = state;

        if state == "CRUISE" || state == "FAULT"
            break;
        end

        t = t + dt;
        idx = idx + 1;
    end

    timeLog = timeLog(1:idx);
    aircraftAltLog = aircraftAltLog(1:idx);
    cabinAltLog = cabinAltLog(1:idx);
    diffPressureLog = diffPressureLog(1:idx);
    stateLog = stateLog(1:idx);

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