<?php
declare(strict_types=1);
namespace OCA\E2EEarlyParams\AppInfo;
use OCP\AppFramework\App;
use OCP\AppFramework\Bootstrap\IBootContext;
use OCP\AppFramework\Bootstrap\IBootstrap;
use OCP\AppFramework\Bootstrap\IRegistrationContext;
use OCP\IRequest;
class Application extends App implements IBootstrap {
	public function __construct() {
		parent::__construct('e2e_early_params');
	}
	public function register(IRegistrationContext $context): void {
	}
	public function boot(IBootContext $context): void {
		// Like any app that looks at a request parameter while booting, before the router has matched the URL.
		// That decodes the request body early, so a parameter set in both the URL and the body takes the URL's
		// value. Plain test servers have no such app, so without this the tests miss what real servers do.
		$context->getServerContainer()->get(IRequest::class)->getParam('e2e');
	}
}
