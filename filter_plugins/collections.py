def pluck(collection, key):
    '''
    Extract item[key] for every item in the collection.
    '''

    return [item[key] for item in collection]

def pluckWithKey(collection, key):
    '''
    Extract key:item[key] for every item in the collection.
    '''

    return [{key:item[key]} for item in collection]

class FilterModule(object):
    '''
    Custom jinja2 filters for working with collections.
    '''

    def filters(self):
        return {
            'pluck': pluck,
            'pluck_with_key': pluckWithKey
        }
