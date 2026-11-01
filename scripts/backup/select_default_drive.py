"""Select only the signed-in user's default OneDrive returned by Microsoft Graph."""
def default_drive_id(question, drive):
    option = question.get('Option') or {}
    if option.get('Name') != 'config_driveid' or not question.get('State'):
        raise ValueError('provider is not waiting for drive selection')
    if drive.get('driveType') not in ('personal','business') or not drive.get('id'):
        raise ValueError('default drive is not an owned OneDrive')
    matches = [x for x in option.get('Examples',[]) if x.get('Value') == drive['id']]
    if len(matches) != 1:
        raise ValueError('default OneDrive is absent or ambiguous')
    return drive['id']
