import { Controller } from '@hotwired/stimulus';

export default class extends Controller {
  static targets = ['input', 'icon'];

  toggle() {
    const input = this.inputTarget;
    const isPassword = input.type === 'password';
    input.type = isPassword ? 'text' : 'password';

    if (this.hasIconTarget) {
      this.iconTarget.textContent = isPassword ? 'visibility_off' : 'visibility';
    }
  }
}
