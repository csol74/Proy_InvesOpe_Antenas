%% =====================================================================
%  PROYECTO SET COVER - EXACTO (intlinprog) vs ALGORITMO GENETICO
%  Ejecutar este script completo (F5). Requiere Optimization Toolbox.
%  Muestra el avance en consola y al final imprime (y guarda en
%  resumen_para_informe.txt) todo lo que se necesita para el Word.
% =====================================================================
clear; clc; close all;

%% 1. PARAMETROS (ajuste aqui para acortar o alargar la ejecucion) -------
archivoCSV  = 'set_cover_500x500.csv';
archivoXLSX = 'Costo_S.xlsx';

% ---- Metodo exacto ----
opcEx.tiempoMax = 28800;   % [s] limite = 8 horas
opcEx.tolRel    = 1e-3;    % se detiene si la brecha vs la cota es <= 0.1 %
opcEx.tolAbs    = 0.99;    % costos enteros: brecha < 1 prueba optimalidad
opcEx.display   = 'iter';  % 'iter' = muestra el progreso del solver en consola
usarArranqueGA  = true;    % true: el solver parte de una solucion rapida del AG
                           % (acelera mucho el B&B; se reporta como "arranque")

% ---- Algoritmo genetico (configuracion RELAJADA) ----
nCorridas = 30;            % bajar a 10 si tarda demasiado
pGA = struct('popSize',200, 'maxGen',3000, 'pc',0.9, 'pm',0.005, ...
             'torneo',3, 'elite',3, ...
             'tiempoMax',600, ...                    % tope por corrida: 10 min (30 corridas = 5 h max.)
             'paciencia',200, 'maxReinicios',3, ...  % reinicio tras 200 gens sin mejora (max. 3)
             'tolMejora',1e-6, 'ventana',500);       % para si en 500 gens mejora < 0.0001 %
frecProgreso = 50;         % imprime avance del AG cada 50 generaciones

if ~exist('figuras','dir'), mkdir('figuras'); end
fidTxt = fopen('resumen_para_informe.txt','w');  fids = [1 fidTxt];
T0 = tic;

%% 2. CARGA DE DATOS -----------------------------------------------------
[A, c, m, n] = cargar_datos(archivoCSV, archivoXLSX);
imp(fids,'Instancia: %d clientes x %d antenas | densidad = %.2f%%\n', m, n, 100*mean(A(:)));
imp(fids,'Costos: min = %d, max = %d, media = %.1f\n', min(c), max(c), mean(c));
imp(fids,'Cobertura por antena: min=%d max=%d | antenas por cliente: min=%d max=%d\n', ...
        min(sum(A,1)), max(sum(A,1)), min(sum(A,2)), max(sum(A,2)));

%% 3. SOLUCION EXACTA ----------------------------------------------------
fprintf('\n=== SOLUCION EXACTA (intlinprog) ===\n');
tArranque = 0;  fArranque = NaN;
if usarArranqueGA
    fprintf('Generando solucion de arranque con el AG (rapida)...\n');
    pA = struct('popSize',100,'maxGen',300,'paciencia',60,'maxReinicios',0,'semilla',999);
    [xA, fArranque, iA] = ga_setcover(A, c, pA);
    tArranque = iA.tiempo;
    fprintf('Arranque: costo = %.0f (%d antenas) en %.1f s\n\n', fArranque, nnz(xA), tArranque);
    opcEx.x0 = xA;
end
fprintf('Iniciando el solver (se ira mostrando el progreso)...\n');
resEx = resolver_exacto(A, c, opcEx);
fprintf('\nSolver terminado: %s\n', resEx.estado);

%% 4. ALGORITMO GENETICO (varias corridas) ------------------------------
fprintf('\n=== ALGORITMO GENETICO (%d corridas) ===\n', nCorridas);
fGA = zeros(nCorridas,1); tGA = zeros(nCorridas,1); nSelGA = zeros(nCorridas,1);
genGA = zeros(nCorridas,1); xGA = false(nCorridas, n); histGA = cell(nCorridas,1);
motGA = cell(nCorridas,1);
for r = 1:nCorridas
    p = pGA;  p.semilla = r;
    p.onGen = @(g,fb,h) progresoGA(g,fb,r,nCorridas,frecProgreso);
    [x, f, info] = ga_setcover(A, c, p);
    fGA(r) = f;  tGA(r) = info.tiempo;  nSelGA(r) = info.nSel;
    genGA(r) = info.generaciones;  xGA(r,:) = x;  histGA{r} = info;  motGA{r} = info.motivo;
    fprintf('>> Corrida %2d/%d terminada | costo = %6.0f | antenas = %3d | gens = %4d | t = %7.1f s | %s\n', ...
            r, nCorridas, f, info.nSel, info.generaciones, info.tiempo, info.motivo);
end
[fMejor, rMejor] = min(fGA);

%% 5. ESTADISTICAS ------------------------------------------------------
fEx   = resEx.fval;
gap   = @(v) 100*(v - fEx)/fEx;                  % vs mejor solucion del solver
gapCota = @(v) 100*(v - resEx.cota)/v;           % vs cota inferior (garantia)
nIgual = sum(fGA <= fEx + 1e-6);

Metodo = {'Exacto (intlinprog)'; 'AG - mejor'; 'AG - promedio'; 'AG - peor'};
Costo  = [fEx; fMejor; mean(fGA); max(fGA)];
Gap_pct = [0; gap(fMejor); gap(mean(fGA)); gap(max(fGA))];
Tiempo_s = [resEx.tiempo; tGA(rMejor); mean(tGA); max(tGA)];
NumAntenas = [resEx.nSel; nSelGA(rMejor); mean(nSelGA); max(nSelGA)];
T = table(Metodo, Costo, Gap_pct, Tiempo_s, NumAntenas);
writetable(T, 'resultados_resumen.xlsx');
Tcorridas = table((1:nCorridas)', fGA, tGA, genGA, nSelGA, motGA, ...
    'VariableNames', {'Corrida','Costo','Tiempo_s','Generaciones','NumAntenas','Motivo'});
writetable(Tcorridas, 'resultados_corridas_AG.xlsx');
save('resultados_setcover.mat','resEx','fGA','tGA','xGA','histGA','T','pGA','pA','opcEx','nCorridas','tArranque','fArranque');

%% 6. RESUMEN PARA EL INFORME (consola + resumen_para_informe.txt) -------
imp(fids,'\n\n################ DATOS PARA EL INFORME WORD ################\n');
imp(fids,'\n--- TABLA 4. Metodo exacto ---\n');
imp(fids,'Costo (mejor solucion) Z*      : %.0f\n', fEx);
imp(fids,'Cota inferior (relajacion LP)  : %.2f\n', resEx.zLP);
imp(fids,'Mejor cota inferior del solver : %.2f\n', resEx.cota);
imp(fids,'Brecha vs cota                 : %.4f %%\n', resEx.gapPct);
imp(fids,'Antenas seleccionadas (%d)     : %s\n', resEx.nSel, mat2str(resEx.seleccion));
imp(fids,'Tiempo del solver [s]          : %.1f (%.2f h)\n', resEx.tiempo, resEx.tiempo/3600);
if usarArranqueGA, imp(fids,'Arranque con AG: costo %.0f en %.1f s (sumar al tiempo si se desea)\n', fArranque, tArranque); end
imp(fids,'Nodos explorados               : %d\n', resEx.nodos);
imp(fids,'exitflag                       : %d\n', resEx.exitflag);
imp(fids,'Estado                         : %s\n', resEx.estado);
imp(fids,'Optimalidad comprobada?        : %s\n', ternario(resEx.optimo,'Si','No'));
imp(fids,'Parametros: tiempoMax=%g s, tolRel=%g, tolAbs=%g, arranque AG=%d\n', ...
        opcEx.tiempoMax, opcEx.tolRel, opcEx.tolAbs, usarArranqueGA);

imp(fids,'\n--- TABLA 5. Algoritmo genetico (%d corridas) ---\n', nCorridas);
imp(fids,'Mejor costo                     : %.0f\n', fMejor);
imp(fids,'Costo promedio +- desv. est.    : %.2f +- %.2f\n', mean(fGA), std(fGA));
imp(fids,'Peor costo                      : %.0f\n', max(fGA));
imp(fids,'Corridas que igualan al exacto  : %d de %d\n', nIgual, nCorridas);
imp(fids,'Tiempo promedio por corrida [s] : %.1f (min %.1f, max %.1f)\n', mean(tGA), min(tGA), max(tGA));
imp(fids,'Generaciones promedio           : %.1f\n', mean(genGA));
imp(fids,'Antenas en la mejor solucion    : %d\n', nSelGA(rMejor));
imp(fids,'Parametros AG: N=%d, G=%d, pc=%.2f, pm=%.4f, k=%d, elite=%d, paciencia=%d, reinicios=%d, tol=%g, ventana=%d\n', ...
        pGA.popSize,pGA.maxGen,pGA.pc,pGA.pm,pGA.torneo,pGA.elite,pGA.paciencia,pGA.maxReinicios,pGA.tolMejora,pGA.ventana);

imp(fids,'\n--- TABLA 6. Comparacion ---\n');
imp(fids,'%-22s %9s %9s %11s %9s\n','Metodo','Costo','Gap[%]','Tiempo[s]','Antenas');
for i = 1:height(T)
    imp(fids,'%-22s %9.1f %9.3f %11.1f %9.1f\n', T.Metodo{i}, T.Costo(i), T.Gap_pct(i), T.Tiempo_s(i), T.NumAntenas(i));
end
imp(fids,'Gap del mejor AG vs cota inferior: %.3f %%  |  del AG promedio: %.3f %%\n', gapCota(fMejor), gapCota(mean(fGA)));

imp(fids,'\n--- TEXTO SUGERIDO PARA LA SECCION 4.3 ---\n');
if fMejor < fEx - 1e-6
    q = sprintf('El AG obtuvo una solucion MEJOR que la entregada por el solver (%.0f frente a %.0f), lo que ocurre porque el solver se detuvo con una brecha de %.3f %% respecto a su cota.', fMejor, fEx, resEx.gapPct);
elseif abs(fMejor - fEx) <= 1e-6
    q = sprintf('El AG alcanzo el costo de la solucion exacta (%.0f) en %d de %d corridas; su costo promedio fue %.1f, a %.3f %% del exacto.', fEx, nIgual, nCorridas, mean(fGA), gap(mean(fGA)));
else
    q = sprintf('La mejor solucion del AG (%.0f) quedo a %.3f %% de la solucion exacta (%.0f); el promedio de las %d corridas estuvo a %.3f %%.', fMejor, gap(fMejor), fEx, nCorridas, gap(mean(fGA)));
end
imp(fids,'Calidad de la solucion. %s\n', q);
imp(fids,'Tiempo de computo. El solver exacto requirio %.1f s (%.2f h) y el AG %.1f s en promedio por corrida; el AG fue %.1f veces %s.\n', ...
        resEx.tiempo, resEx.tiempo/3600, mean(tGA), max(resEx.tiempo,mean(tGA))/min(resEx.tiempo,mean(tGA)), ...
        ternario(mean(tGA)<resEx.tiempo,'mas rapido','mas lento'));
imp(fids,'Comportamiento. Las corridas se detuvieron por: %s.\n', strjoin(unique(motGA)', ', '));
imp(fids,'\nTiempo total de este script: %.2f h\n', toc(T0)/3600);
imp(fids,'Archivos: resultados_resumen.xlsx, resultados_corridas_AG.xlsx, resultados_setcover.mat, carpeta figuras/\n');
fclose(fidTxt);

%% 7. FIGURAS PARA EL INFORME -------------------------------------------
h = histGA{rMejor};
fig1 = figure('Color','w','Position',[100 100 760 440]);
plot(h.mejorHist,'b-','LineWidth',2); hold on;
plot(h.mediaHist,'Color',[0.85 0.4 0.1],'LineWidth',1.3);
yline(fEx,'k--','LineWidth',1.5);
yline(resEx.cota,'g:','LineWidth',1.5);
xlabel('Generacion'); ylabel('Costo total'); grid on;
legend('Mejor del AG','Promedio poblacion','Solucion exacta','Cota inferior','Location','northeast');
title(sprintf('Convergencia del AG (corrida %d)', rMejor));
exportgraphics(fig1,'figuras/fig_convergencia.png','Resolution',300);

fig2 = figure('Color','w','Position',[100 100 760 440]); hold on;
for r = 1:nCorridas, plot(histGA{r}.mejorHist,'Color',[0.2 0.4 0.9 0.35]); end
yline(fEx,'k--','LineWidth',1.5);
xlabel('Generacion'); ylabel('Mejor costo'); grid on;
title(sprintf('Convergencia de las %d corridas del AG', nCorridas));
exportgraphics(fig2,'figuras/fig_convergencia_todas.png','Resolution',300);

fig3 = figure('Color','w','Position',[100 100 760 440]);
histogram(fGA, 'FaceColor',[0.2 0.5 0.8]); hold on;
xline(fEx,'k--','LineWidth',2,'Label','Solucion exacta');
xlabel('Costo final del AG'); ylabel('Frecuencia'); grid on;
title('Distribucion del costo final del AG');
exportgraphics(fig3,'figuras/fig_distribucion_AG.png','Resolution',300);

fig4 = figure('Color','w','Position',[100 100 900 400]);
subplot(1,2,1);
bar([fEx, fMejor, mean(fGA)]); set(gca,'XTickLabel',{'Exacto','AG mejor','AG medio'});
ylabel('Costo total'); title('Calidad de la solucion'); grid on;
subplot(1,2,2);
bar([resEx.tiempo, mean(tGA)]); set(gca,'XTickLabel',{'Exacto','AG (medio)'});
ylabel('Tiempo [s]'); title('Tiempo de computo'); grid on;
exportgraphics(fig4,'figuras/fig_comparacion.png','Resolution',300);

fig5 = figure('Color','w','Position',[100 100 900 400]);
subplot(1,2,1); bar(A*double(resEx.x(:))); title('Exacto: antenas por cliente'); xlabel('Cliente'); grid on;
subplot(1,2,2); bar(A*double(xGA(rMejor,:)')); title('AG: antenas por cliente'); xlabel('Cliente'); grid on;
exportgraphics(fig5,'figuras/fig_cobertura.png','Resolution',300);

fprintf('\nListo. Revise resumen_para_informe.txt y la carpeta /figuras\n');

%% ---------------- funciones locales ----------------
function imp(fids, fmt, varargin)
    for k = 1:numel(fids), fprintf(fids(k), fmt, varargin{:}); end
end
function progresoGA(g, fb, r, R, frec)
    if mod(g, frec) == 0
        fprintf('   [corrida %d/%d] generacion %5d | mejor costo = %.0f\n', r, R, g, fb);
    end
end
function s = ternario(cond, a, b)
    if cond, s = a; else, s = b; end
end
