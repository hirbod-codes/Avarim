enum Status { active, canceled, trial, paymentNotVerified, paymentNotCompleted, inDebtToUser }

Status toStatus(String str) {
  switch (str) {
    case 'active':
      return Status.active;
    case 'canceled':
      return Status.canceled;
    case 'trial':
      return Status.trial;
    case 'paymentNotVerified':
      return Status.paymentNotVerified;
    case 'paymentNotCompleted':
      return Status.paymentNotCompleted;
    case 'inDebtToUser':
      return Status.inDebtToUser;
    default:
      throw Exception('Invalid status provided');
  }
}
