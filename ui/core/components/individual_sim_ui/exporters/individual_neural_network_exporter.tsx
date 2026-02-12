import { ref } from 'tsx-vanilla';
import { IndividualSimUI } from '../../../individual_sim_ui';
import { Spec } from '../../../proto/common';
import { RaidSimRequest, RaidSimResult } from '../../../proto/api';
import { BaseModal } from '../../base_modal';
import { downloadString } from '../../../utils';

export class IndividualNeuralNetworkExporter<SpecType extends Spec> extends BaseModal {
	private readonly simUI: IndividualSimUI<SpecType>;

	constructor(parent: HTMLElement, simUI: IndividualSimUI<SpecType>) {
		super(parent, 'neural-network-exporter', { title: 'Export for Neural Network', footer: true });
		this.simUI = simUI;

		this.body.innerHTML = `
			<p>This tool runs a 1-iteration simulation with detailed debug logging enabled and exports the full result as a JSON file. This is useful for analyzing rotation, resource management, and APL decisions for neural network training.</p>
			<p>The exported file will contain the original request (including APL settings) and the full simulation results with logs.</p>
		`;

		const exportBtnRef = ref<HTMLButtonElement>();
		this.footer!.appendChild(
			<button className="btn btn-primary" ref={exportBtnRef} onclick={() => this.runAndExport()}>
				<i className="fa fa-play me-1"></i>
				Run and Export
			</button>
		);
	}

	private async runAndExport() {
		const result = await this.simUI.runSimOnce();
		if (result) {
			const data = JSON.stringify({
				request: RaidSimRequest.toJson(result.request),
				result: RaidSimResult.toJson(result.result),
			}, null, 2);
			downloadString(data, 'wowsims_neural_net.json');
		}
	}
}
