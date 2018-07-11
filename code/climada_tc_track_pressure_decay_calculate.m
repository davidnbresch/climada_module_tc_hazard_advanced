function [tc_track, p_rel] = climada_tc_track_pressure_decay_calculate(tc_track, check_plot)

% MODULE:
%   tropical_cyclone
% NAME:
%   climada_tc_track_pressure_decay_calculate
% PURPOSE:
%   Calculate pressure decay after landfall based on historical tc tracks
%   for:  isimip_windfield_holland
% CALLING SEQUENCE:
%     [~,p_rel_v]  = climada_tc_track_wind_decay_calculate(tc_track,check_plots);
%     tc_track_decay = climada_tc_track_wind_decay(tc_track_prob, p_rel_v, check_plots);
%     [~,p_rel_p]  = climada_tc_track_pressure_decay_calculate(tc_track,check_plots);
%     tc_track_decay = climada_tc_track_pressure_decay(tc_track_decay, p_rel_p, check_plots);
%     hazard   = isimip_tc_hazard_set(tc_track_decay,hazard_file,centroids);
%     hazard = climada_hazard_reset_yearset(hazard,1);
%     save([climada_global.hazards_dir filesep 'hazard_file'],'hazard','-v7.3');
%
% EXAMPLE:
%   [tc_track p_rel] = climada_tc_track_pressure_decay_calculate(tc_track)
% INPUTS:
%   none, if tc_track empty prompted for
% OPTIONAL INPUT PARAMETERS:
%   check_plot: to create plot
% OUTPUTS:
%   p_rel contains the parameters for exponential decay for tropical
%   depression, tropical storm and hurricanes category 1 to 5
%   pressure decay = S-(S-1)*exp(-A*x), where A = p_rel(1,1), S=EnvironmentalPressure/PressureAtLandfall=p_rel(1,2)
%   A = p_rel(1,1), S = p_rel(1,2)
% RESTRICTIONS:
%   changes CentralPressure only.
% MODIFICATION HISTORY:
% Samuel Eberenz, eberenz@posteo.eu, 20180709, adapted from climada_tc_track_wibd_decay_calculate to change CentralPressure p instead of MaxSustainedWind v (not yet fully documented)
%-

% init global variables
global climada_global
if ~climada_init_vars, return; end

% check inputs, and set default values
if ~exist('tc_track'       , 'var'), tc_track      = []  ; end
if ~exist('p_rel'          , 'var'), p_rel         = []  ; end
if ~exist('check_plot'     , 'var'), check_plot    = 1   ; end

% prompt for tc_track if not given
if isempty(tc_track)
    tc_track             = [climada_global.data_dir filesep 'tc_tracks' filesep '*.mat'];
    tc_track_default     = [climada_global.data_dir filesep 'tc_tracks' filesep 'Select HISTORICAL tc track .mat'];
    [filename, pathname] = uigetfile(tc_track, 'Select HISTORIAL tc tracks:',tc_track_default);
    if isequal(filename,0) || isequal(pathname,0)
        return; % cancel
    else
        tc_track = fullfile(pathname,filename);
    end
end
% load the tc track set, if a filename has been passed
if ~isstruct(tc_track)
    tc_track_file = tc_track;
    tc_track      = [];
    load(tc_track_file);
end

% number of generated and historical tracks
no_ori = sum([tc_track(:).orig_event_flag]);
no_gen = length(tc_track)/no_ori;


%% check for historical tracks
gen_tracks = find(~[tc_track(:).orig_event_flag]);
if ~isempty(gen_tracks)
    fprintf('Warning: Not all tracks are historical. Please rerun with historical tracks.\n')
    no_gen = 1;
    %return
end

% refine tc_tracks to 1 h
tc_track = climada_tc_equal_timestep(tc_track,1);

%% find nodes on land and over sea
tc_track = climada_tc_on_land(tc_track);

max_h_lf = 72; % max time after landfall
v_scale_kn   = [34 64 83 96 113 135 500];
no_cat       = size(v_scale_kn,2);
p_vs_lf_time = cell(1,no_cat);
S_rel_to_env = 1; % if = 1, decay to environmental pressure, otherwise to last central pressure of storm track;
S_cell = cell(1,no_cat);


%% calculate exponential decay of wind speed after landfall if not given
% plot wind speed after land fall of historical tracks
% climada_figuresize(0.5,0.8);
% plot([0 0],[0 150],':k')
% hold on
% xlim([0 150])
% ylim([0 150])
% ylabel('Wind speed (kn)')
% xlabel('Time after landfall (h)')
for t_i = 1:no_gen:length(tc_track)
    land_index_ = find(diff(tc_track(t_i).onLand) == 1)+1;
    sea_index_  = find(diff(tc_track(t_i).onLand) ==-1)+1;
    sea_index_  = [sea_index_ size(tc_track(t_i).onLand,2)];

    if ~isempty(land_index_)
        if length(sea_index_)<= length(land_index_)   
            % time over land
            onland_time = sea_index_ - land_index_(1:length(sea_index_));
            for lf_i = 1:length(onland_time)
                p_landfall  = tc_track(t_i).CentralPressure(land_index_(lf_i)-1);

                v_landfall  = tc_track(t_i).MaxSustainedWind(land_index_(lf_i)-1);
                scale_index = find(v_landfall < v_scale_kn);
                if ~isempty(scale_index)
                    scale_index = scale_index(1);
                    a           = onland_time(lf_i);
                    p_vs_lf_time{scale_index}(1:a+1,end+1) = tc_track(t_i).CentralPressure(land_index_(lf_i)-1+[0:a])';
                    if S_rel_to_env
                        S_cell{scale_index}(1:a+1,end+1) = max(1010,tc_track(t_i).EnvironmentalPressure(end))/min(1009,p_landfall);
                    else
                        S_cell{scale_index}(1:a+1,end+1) = tc_track(t_i).CentralPressure(end)/p_landfall;
                    end
                end
            end %lf_i
        end
    end
end %loop over historical tracks

% put into one structure and set zeros to nan
for cat_i = 1:no_cat
    p_vs_lf_time{cat_i}(p_vs_lf_time{cat_i} == 0) = nan;
    S_cell{cat_i}(S_cell{cat_i} == 0) = nan;
end
%% create figure
% climada_figuresize(0.5,0.8);
% % plot([0 0],[0 150],':k')
% hold on
% xlim([-5 150])
% ylim([0 150])
% ylabel('Wind speed (kn)')
% xlabel('Time after landfall (h)')
% for cat_i = 1:no_cat
%     g = plot( [0:size(v_vs_lf_time{cat_i},1)-1],...
%               v_vs_lf_time{cat_i},'.','color',cmap(cat_i,:));
%     h(cat_i) = g(1);
%     %semilogy(v_vs_lf_time{cat_i},'.','color',cmap(cat_i,:))
%     hold on
% end
% legend(h,'Tropical Depression','Tropical Storm','Hurrican Cat. 1','Hurrican Cat. 2','Hurrican Cat. 3','Hurrican Cat. 4','Hurrican Cat. 5' )
% title('Historical tracks')
%% fit exponential decay
% p = zeros(no_cat,2);
% for cat_i = 1:no_cat
%     x = repmat([1:size(v_vs_lf_time{cat_i},1)]',size(v_vs_lf_time{cat_i},2),1);
%     y = v_vs_lf_time{cat_i}(:);
%     p(cat_i,:) = polyfit(x(~isnan(y)), log(y(~isnan(y))),1);
% end
% % create figure with fitted functions
% climada_figuresize(0.5,0.8);
% hold on
% xlim([-5 150])
% ylim([0 150])
% ylabel('Wind speed (kn)')
% xlabel('Time after landfall (h)')
% no_cat = size(v_vs_lf_time,2);
% cmap   = jet(no_cat);
% for cat_i = 1:no_cat
%     plot( [0:size(v_vs_lf_time{cat_i},1)-1],...
%            v_vs_lf_time{cat_i},'.','color',cmap(cat_i,:),'markersize',5);
% end
% for cat_i = 1:no_cat
%     x_fit = [0:2:150];
%     y_fit = polyval(p(cat_i,:),x_fit);
%     g = plot(x_fit,exp(y_fit),'.-','color',cmap(cat_i,:));
%     h(cat_i) = g(1);
%     %semilogy(v_vs_lf_time{cat_i},'.','color',cmap(cat_i,:))
%     hold on
% end
% legend(h,'Tropical Depression','Tropical Storm','Hurrican Cat. 1','Hurrican Cat. 2','Hurrican Cat. 3','Hurrican Cat. 4','Hurrican Cat. 5' )
% title('Wind speed decay in relation to time after landfall')

%% relative decay for different categories
for cat_i = 1:no_cat
    p_vs_lf_time_relative{cat_i} = bsxfun(@rdivide,p_vs_lf_time{cat_i},p_vs_lf_time{cat_i}(1,:));
end

%% fit exponential decay with intercept 1 at landfall
% pressure decay = S-(S-1)*exp(x*A), where S=LastPressure/PressureAtLandfall=p_rel(1,2), A = p_rel(1,1)
p_rel = zeros(no_cat,2);
for cat_i = 1:no_cat
    x = repmat([1:size(p_vs_lf_time_relative{cat_i},1)]',size(p_vs_lf_time_relative{cat_i},2),1);
    y = p_vs_lf_time_relative{cat_i}(:);
    S = S_cell{cat_i}(:);
    y((S-y)<=0)=NaN;
    y(S<=1)=NaN;
    %B = log(y(~isnan(y))) ./ x(~isnan(y)) ;
    A = log((S(~isnan(y))-1)./(S(~isnan(y))-y(~isnan(y)))) ./ x(~isnan(y));
    p_rel(cat_i,1) = mean(A);
    p_rel(cat_i,2) = mean(S(~isnan(y)));
end
nan_index = isnan(p_rel(:,1));
n_nan     = find(~nan_index);
for cat_i = 1:no_cat
    if isnan(p_rel(cat_i,1))
        [c closest]    = min(abs(cat_i-n_nan));
        p_rel(cat_i,1) = p_rel(n_nan(closest(1)),1);
        p_rel(cat_i,2) = p_rel(n_nan(closest(1)),2);
        fprintf('No historical track Category %d. Take wind decay parameters from Category %d\n', cat_i-2, n_nan(closest(1))-2)
    end
end


if check_plot
    % create figure with fitted functions, relative decay
    h = zeros(1,no_cat);
    climada_figuresize(0.5,0.8);
    hold on
    xlim([-5 150])
    ylim([0.9 1.2])
    ylabel('Relative wind speed (on landfall = 1)')
    timestep  = datenum(0,0,diff(tc_track(1).datenum(1:2)))*24;
    xlabelstr = sprintf('Time steps after landfall (h)');
    xlabel(xlabelstr)
    cmap   = jet(no_cat);
    for cat_i = 1:no_cat
        if ~isempty(p_vs_lf_time{cat_i})
            hg = plot( [0:size(p_vs_lf_time{cat_i},1)-1],...
                              p_vs_lf_time_relative{cat_i},'.','color',cmap(cat_i,:),'markersize',5);
            h(cat_i) = hg(1);              
        end
    end
    %p_rel = p_rel*2;
    x_fit = [1:0.5:150];
    for cat_i = 1:no_cat
        y_fit = p_rel(cat_i,2)-(p_rel(cat_i,2)-1)*exp(-p_rel(cat_i,1)*x_fit);
        %y_fit = polyval(p_rel(cat_i,:),x_fit);
        g = plot(x_fit,y_fit,'-','color',cmap(cat_i,:));
        h(cat_i) = g(1);
        %semilogy(v_vs_lf_time{cat_i},'.','color',cmap(cat_i,:))
        hold on
    end
    
    legendstr = {'Tropical Depression','Tropical Storm','Hurrican Cat. 1','Hurrican Cat. 2','Hurrican Cat. 3','Hurrican Cat. 4','Hurrican Cat. 5'};
    for cat_i = 1:no_cat
        legendstr{cat_i} = sprintf('%s,   y = %1.3f-%1.3f*exp(%1.4f x)',legendstr{cat_i},p_rel(cat_i,2),p_rel(cat_i,2)-1, -p_rel(cat_i,1));
    end
    legend(h,legendstr)
    title('Relative pressure decay in relation to time after landfall')
end %check_plot






