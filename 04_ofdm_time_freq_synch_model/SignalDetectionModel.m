%%
% Signal Detection

%%
% Параметры
% close all;
path(path, './functions/');
path(path, '../02_ofdm_phy_802_11a_model/ofdm_phy_802_11a/');

N_subcarrier = 64;
N_ofdm_sym   = 2;
N_bit        = N_ofdm_sym * N_subcarrier;
Fd           = 10 * 10^6;

window_mode = 'no_window_overlap'; % 'window_overlap' or 'no_window_overlap' // параметр ПРЕАМБУЛЫ
graph_mode  = 'no_display'; % 'dispaly' or 'no_display'

dcOffset_mode = 'no_dc_offset'; % 'dc_offset' or 'no_dc_offset', добавляем или не добавляем постоянную составляющую к rx сигналу
dcOffset = 1 + 1i * 1; % значение постоянной составляющей для I и Q канала
filter_mode = 'filter'; % 'no_filter' - ФВЧ не используется   or   'filter' - ФВЧ используется для удаления DC-offset

awgn_mode = 'awgn'; % 'awgn' or 'no_awgn': задаём есть ли шум в канале или нет
EbNo = [0, 5, 10]; % дБ

N_iter      = 1e3; % кол-во итераций для накопления статистики
time_offset = 200;
deltaF      = [0, 10e3, 50e3] ;%: 50 * 10^3 : 100 * 10^3; % Гц, частотная отстройка

% Алгоритм обнаружения
L_detection = 144; % размер окна суммирования
D_s = 16; % длина одного STS
sig_detection_threshold = 0.25; % надо подбирать в зависимости от Eb/No


%%
% Модель
tx_bit = randi([0 1], 1, N_bit);

% BPSK
tx_bpsk_sym = complex( zeros(1, N_bit) );
tx_bpsk_sym(tx_bit == 1) = -1 + 1i * 0;
tx_bpsk_sym(tx_bit == 0) = +1 + 1i * 0;

% OFDM
tx_ofdm_sym = reshape(tx_bpsk_sym, N_subcarrier, N_ofdm_sym);
tx_ofdm_sym = ifft(tx_ofdm_sym, N_subcarrier);
tx_ofdm_sym = reshape(tx_ofdm_sym, 1, N_bit);

Eb = sum( abs(tx_ofdm_sym) .^ 2 ) / N_bit;

% Add preamble
if strcmp(window_mode, 'window_overlap')

	STS = GenerateSTS('Tx');
	LTS = GenerateLTS('Tx');
	preamble = [ STS(1 : end  - 1), ... % STS
	             STS(end) + LTS(1), LTS(2 : end - 1), ... % LTS // с учётом перекрытия
	             LTS(end) ]; % кусок перекрытия для следующего OFDM-символа
	txSig = [ preamble(1 : end - 1), ... % преамбула
	          preamble(end) + 0.5 * tx_ofdm_sym(1), tx_ofdm_sym(2 : end)]; % полезная нагрузка с учётом перекрытия

else % strcmp(window_mode, 'no_window_overlap')

	STS = GenerateSTS('Rx');
	LTS = GenerateLTS('Rx');
	preamble    = [STS, LTS];
	txSig = [preamble, tx_ofdm_sym]; % полезная нагрузка с учётом перекрытия

end


% AWGN + time_offset + freq_offset
signalDetectionSample_3d = zeros(N_iter, length(deltaF), length(EbNo));
for k = 1 : N_iter

	for j = 1 : length(deltaF)

		for i = 1 : length(EbNo)

			if strcmp(awgn_mode, 'awgn')
				No = Eb / ( 10^(EbNo(i) / 10) );
			else
				No = 0; % minus AWGN
			end

			rxSig = [         sqrt(No / 2) * randn(1, time_offset)   + 1i * sqrt(No / 2) * randn(1, time_offset), ...
					  txSig + sqrt(No / 2) * randn(1, length(txSig)) + 1i * sqrt(No / 2) * randn(1, length(txSig)), ...
							  sqrt(No / 2) * randn(1, time_offset) +   1i * sqrt(No / 2) * randn(1, time_offset) ];
			rxSig = rxSig .* exp(1i * 2 * pi * deltaF(j) * (1 : length(rxSig)) / Fd);

			% Добавление постоянной составляющей
			if strcmp(dcOffset_mode, 'dc_offset')
				rxSig = rxSig + dcOffset;
			end

			% Убиваем постоянную составляющую
			if strcmp(filter_mode, 'filter')

				% ФВЧ: Equiripple,
				% Fs = 10e6 Hz, Fstop = 100 Hz, Fpass = 4e6 Hz,
				% Astop = 80 dB, Apass = 1 dB
				b = [-0.069011962933607576275996109416155377403, ...
					 -0.24968762861092019811337650025961920619,  ...
					  0.637401352293061496112613895093090832233, ...
					 -0.24968762861092019811337650025961920619,  ...
					 -0.069011962933607576275996109416155377403];
				rxSamples = filter(b, 1, rxSamples);

			end

			% Signal Detection
			[m, signalDetectionSample] = SignalDetection(rxSig, L_detection, D_s, sig_detection_threshold);

			if strcmp(graph_mode, 'display')
				O_sample = 1 : length(m);
				figure;
				hold on;
				plot(O_sample, m);
				stem(time_offset+1, 1.5); % первый отсчёт преамбулы
				stem(signalDetectionSample, 1.2); % отсчёт, на котором обнаружили сигнал
				hold off;
				grid on;
				xlabel('samples');
				ylabel('m = abs(AutoCorr).^2 ./ Energy.^2');
				title({ ['EbNo = ', num2str(EbNo(i)), ' dB'], ...
				        ['deltaF = ', num2str(deltaF(j)), ' Hz'] });
				legend('m', 'FirstSampleOfPreamble', 'SampleOfThresholdExcess');

				if length(EbNo) ~= 1 && length(deltaF) ~= 1
					input('Press Enter to resume\n\n');
				end
			end

			signalDetectionSample_3d(k, j, i) = signalDetectionSample;

		end

	end

end


%%
% Инфа по отсчёту на котором зафиксировали начало полезного сигнала
% Полезно проанализировать, чтобы понять с кого отсчёта
% запускать следующий алгоритм обработки: алгоритм грубой временной синхронизации
for j = 1 : length(deltaF)
	for i = 1 : length(EbNo)
		NoDetectionNum = sum( signalDetectionSample_3d(:, j, i) == Inf );
		fprintf( 'EbNo == %2d dB, deltaF == %7d Hz   Кол-во не сработанных детектирований: %d из %d\n', ...
		         EbNo (i), deltaF(j), NoDetectionNum, N_iter );
	end
end

% Гистограммы, показывающие на каком отсчёте был превышен порог, относительно первого отсчёта преамбулы
if length(EbNo) ~= 1 && length(deltaF) ~= 1
	signalDetectionSample_3d = signalDetectionSample_3d - time_offset;
	signalDetectionSample_3d(signalDetectionSample_3d == Inf) = 100;
	fprintf('\n\nЕсли значение 100, что это значит, что Обнаружитель НЕ СРАБОТАЛ\n\n');
	for j = 1 : length(deltaF)

		figure;

		for i = 1 : length(EbNo) 

			subplot(length(EbNo), 1, i);
			ar_1d = reshape(signalDetectionSample_3d(:, j, i), 1, []); 
			hist(ar_1d, min(ar_1d) : max(ar_1d));
			xlabel('smpls');
			title({ ['EbNo = ', num2str(EbNo(i)), ' dB'], ...
					['deltaF = ', num2str(deltaF(j)), ' Hz'] });
			grid on;

		end
	end

	fprintf(['При отсутствии шума первый пик (если sumWindow == 144, то единтсвенный)\n', ...
			 'будет на первом отсчёте преамбулы (преамбула без перекрытия, иначе если с перекрытием,\n', ...
			 'то на втором отсчёте)\n\n']);
	fprintf(['Превышение порога случится раньше, до отсчётов относящихся к пакету/преамбуле\n', ...
			 '(насколько раньше - определяется порогом)\n\n']);
end