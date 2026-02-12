import { ref } from 'tsx-vanilla';

import { RaidSimRequest, RaidSimResult } from '../../../proto/api';
import { Spec } from '../../../proto/common';
import { downloadString } from '../../../utils';
import type { IndividualSimUI } from '../../../individual_sim_ui';
import { IndividualExporter } from './individual_exporter';

export class IndividualNeuralNetworkExporter<SpecType extends Spec> extends IndividualExporter<SpecType> {
	constructor(parent: HTMLElement, simUI: IndividualSimUI<SpecType>) {
		super(parent, simUI, { title: 'Export for Neural Network', allowDownload: true });

		const description = document.createElement('div');
		description.innerHTML = `
			<div style="margin-top: 10px;">
				<p>Этот инструмент запускает 1 итерацию боя с подробным логом (Debug) и экспортирует результат в JSON для обучения нейросети.</p>
				<p>Файл содержит:</p>
				<ul>
					<li>Настройки персонажа и APL ротацию</li>
					<li>Полный лог событий (урон, ресурсы, баффы)</li>
					<li>Лог принятия решений APL (какое действие было выбрано и почему)</li>
				</ul>
			</div>
		`;
		this.body.prepend(description);

		const exportBtnRef = ref<HTMLButtonElement>();
		this.footer!.appendChild(
			(
				<button className="btn btn-primary" ref={exportBtnRef} onclick={() => this.runAndExport()}>
					<i className="fa fa-play me-1"></i>
					Запустить и Экспортировать
				</button>
			) as HTMLElement,
		);
	}

	getData(): string {
		return 'Нажмите "Запустить и Экспортировать" для генерации файла.';
	}

	private async runAndExport() {
		const result = await this.simUI.runSimOnce();
		if (result) {
			const data = JSON.stringify(
				{
					request: RaidSimRequest.toJson(result.request),
					result: RaidSimResult.toJson(result.result),
				},
				null,
				2,
			);
			downloadString(data, 'wowsims_neural_net.json');
		}
	}
}
