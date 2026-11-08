%% =====================================================================
%  ANALISIS DE SENSIBILIDAD DE PARAMETROS DEL AG
%  Barre tamano de poblacion y tasa de mutacion. Ejecutar despues de
%  main_comparacion.m (usa resultados_setcover.mat para el optimo).
%  Reduzca nCorr si tarda demasiado.
% =====================================================================
clear; clc;
[A, c] = cargar_datos('set_cover_500x500.csv','Costo_S.xlsx');
load('resultados_setcover.mat','resEx');

popList = [50 100 200];
pmList  = [0.002 0.01 0.03];
nCorr   = 10;

Res = [];
for a = 1:numel(popList)
    for b = 1:numel(pmList)
        f = zeros(nCorr,1); t = zeros(nCorr,1);
        for r = 1:nCorr
            p = struct('popSize',popList(a),'pm',pmList(b),'maxGen',300, ...
                       'pc',0.9,'torneo',3,'elite',2,'paciencia',80,'semilla',r);
            [~, f(r), info] = ga_setcover(A, c, p);
            t(r) = info.tiempo;
        end
        Res = [Res; popList(a), pmList(b), min(f), mean(f), std(f), ...
               100*(mean(f)-resEx.fval)/resEx.fval, mean(t)]; %#ok<AGROW>
        fprintf('pop=%3d pm=%.3f | mejor=%.0f media=%.1f gap=%.2f%% t=%.1fs\n', ...
            popList(a), pmList(b), min(f), mean(f), Res(end,6), mean(t));
    end
end
T = array2table(Res, 'VariableNames', {'Poblacion','pm','Mejor','Media','Desv','Gap_pct','Tiempo_s'});
disp(T); writetable(T,'resultados_sensibilidad.xlsx');
